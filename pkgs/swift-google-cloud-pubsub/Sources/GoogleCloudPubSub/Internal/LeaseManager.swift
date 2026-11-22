// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import DequeModule
import Foundation
import GRPCCore
@_spi(GoogleCloudInternal) import GoogleGax
import GoogleRpc
import Logging
import Synchronization
import _GoogleCloudPubSubProtos
import SwiftProtobuf

package final class LeaseManager: Sendable {
  package static let maxAckIDsPerRequest = 1_000
  package static let maxRequestBytes = 512 * 1024
  package static let minExtensionSeconds: Int32 = 10
  package static let minEODExtensionSeconds: Int32 = 60
  package static let maxExtensionSeconds: Int32 = 600
  private static let coalesceWindow: Duration = .milliseconds(5)
  private static let maxLatencySamples = 1_000

  package struct IncomingLeaseItem: Sendable {
    package let ackID: String
    package let leaseTracker: LeaseTracker

    package init(ackID: String, leaseTracker: LeaseTracker) {
      self.ackID = ackID
      self.leaseTracker = leaseTracker
    }
  }

  private struct AckHandler: AckHandlerProtocol, Sendable {
    private let ackID: String
    private let isExactlyOnce: Bool
    private let manager: LeaseManager

    init(ackID: String, isExactlyOnce: Bool, manager: LeaseManager) {
      self.ackID = ackID
      self.isExactlyOnce = isExactlyOnce
      self.manager = manager
    }

    func ack(options: AckOptions) -> AckQueuedResult {
      self.manager.enqueueSettlement(
        ackID: self.ackID,
        kind: .ack,
        isExactlyOnce: self.isExactlyOnce,
        requestOptions: options.request,
        continuation: nil
      )
      return AckQueuedResult()
    }

    func nack(options: NackOptions) -> NackQueuedResult {
      self.manager.enqueueSettlement(
        ackID: self.ackID,
        kind: .nack,
        isExactlyOnce: self.isExactlyOnce,
        requestOptions: options.request,
        continuation: nil
      )
      return NackQueuedResult()
    }

    func ackWithResult(options: AckOptions) async throws -> AckResult {
      try await withCheckedThrowingContinuation { continuation in
        self.manager.enqueueSettlement(
          ackID: self.ackID,
          kind: .ack,
          isExactlyOnce: self.isExactlyOnce,
          requestOptions: options.request,
          continuation: continuation
        )
      }
    }

    func nackWithResult(options: NackOptions) async throws -> AckResult {
      try await withCheckedThrowingContinuation { continuation in
        self.manager.enqueueSettlement(
          ackID: self.ackID,
          kind: .nack,
          isExactlyOnce: self.isExactlyOnce,
          requestOptions: options.request,
          continuation: continuation
        )
      }
    }
  }

  private enum SettlementKind: Sendable {
    case ack
    case nack
  }

  private struct SettlementRequest: Sendable {
    let ackID: String
    let isExactlyOnce: Bool
    let requestOptions: RequestOptions
    let continuation: CheckedContinuation<AckResult, any Error>?
  }

  private struct WeakLeaseTrackerRef: Sendable {
    weak var value: LeaseTracker?
  }

  private struct ActiveLease: Sendable {
    let ackID: String
    let receivedAt: ContinuousClock.Instant
    var maxDeadline: ContinuousClock.Instant
    var leaseTrackers: [WeakLeaseTrackerRef]
    var nextRenewalAt: ContinuousClock.Instant
    let isExactlyOnce: Bool
    var isPendingAck: Bool = false
  }

  private struct IdleWaiter: Sendable {
    let id: UInt64
    let continuation: CheckedContinuation<Bool, Never>
  }

  private struct State: Sendable {
    var renewalsStopped: Bool = false
    var isClosed: Bool = false
    var sessionExactlyOnce: Bool = false
    var activeLeases: [String: ActiveLease] = [:]
    var ackLatenciesSeconds: Deque<Int32> = []
    var renewalLoopGeneration: UInt64 = 0
    var renewalWakeGeneration: UInt64 = 0
    var scheduledWakeAt: ContinuousClock.Instant? = nil
    var renewalSleepCancelBox: (@Sendable () -> Void)? = nil
    var renewalTask: Task<Void, Never>? = nil

    var pendingAcks: [SettlementRequest] = []
    var pendingNacks: [SettlementRequest] = []
    var ackTimerTask: Task<Void, Never>? = nil
    var nackTimerTask: Task<Void, Never>? = nil
    var inFlightSettlementRPCs: Int = 0
    var nextWaiterID: UInt64 = 1
    var idleWaiters: [IdleWaiter] = []
  }

  private let subscription: String
  private let subscribeOptions: SubscribeOptions
  private let subscriptionOverheadBytes: Int
  private let pool: GRPCChannelPool
  private let clock: any PubSubClock
  private let initialNonEODGrace: Duration
  private let state = Mutex(State())

  package init(
    subscription: String,
    subscribeOptions: SubscribeOptions,
    pool: GRPCChannelPool,
    clock: any PubSubClock
  ) {
    self.subscription = subscription
    self.subscribeOptions = subscribeOptions
    let subBytes = subscription.utf8.count
    self.subscriptionOverheadBytes = 1 + Self.varintSize(subBytes) + subBytes
    self.pool = pool
    self.clock = clock
    self.initialNonEODGrace = (clock is SystemPubSubClock) ? .milliseconds(25) : .zero
  }

  package func makeAckHandler(ackID: String, isExactlyOnce: Bool) -> any AckHandlerProtocol {
    AckHandler(ackID: ackID, isExactlyOnce: isExactlyOnce, manager: self)
  }

  package func ack(ackID: String, isExactlyOnce: Bool, options: AckOptions) {
    self.enqueueSettlement(
      ackID: ackID,
      kind: .ack,
      isExactlyOnce: isExactlyOnce,
      requestOptions: options.request,
      continuation: nil
    )
  }

  package func nack(ackID: String, isExactlyOnce: Bool, options: NackOptions) {
    self.enqueueSettlement(
      ackID: ackID,
      kind: .nack,
      isExactlyOnce: isExactlyOnce,
      requestOptions: options.request,
      continuation: nil
    )
  }

  package func ackWithResult(
    ackID: String,
    isExactlyOnce: Bool,
    options: AckOptions
  ) async throws -> AckResult {
    try await withCheckedThrowingContinuation { continuation in
      self.enqueueSettlement(
        ackID: ackID,
        kind: .ack,
        isExactlyOnce: isExactlyOnce,
        requestOptions: options.request,
        continuation: continuation
      )
    }
  }

  package func nackWithResult(
    ackID: String,
    isExactlyOnce: Bool,
    options: NackOptions
  ) async throws -> AckResult {
    try await withCheckedThrowingContinuation { continuation in
      self.enqueueSettlement(
        ackID: ackID,
        kind: .nack,
        isExactlyOnce: isExactlyOnce,
        requestOptions: options.request,
        continuation: continuation
      )
    }
  }

  package var activeLeaseCount: Int {
    self.state.withLock { $0.activeLeases.count }
  }

  package var activeAckIDs: [String] {
    self.state.withLock { Array($0.activeLeases.keys) }
  }

  package func initialExtensionSeconds(isExactlyOnce: Bool) -> Int32 {
    self.state.withLock { state in
      self.targetDeadlineSecondsLocked(isExactlyOnce: isExactlyOnce, state: state)
    }
  }

  package func registerBatch(
    _ items: [IncomingLeaseItem],
    isExactlyOnce: Bool
  ) async -> [IncomingLeaseItem] {
    guard !items.isEmpty else { return [] }

    let (shouldStop, targetSeconds) = self.state.withLock { state -> (Bool, Int32) in
      state.sessionExactlyOnce = isExactlyOnce
      let target = self.targetDeadlineSecondsLocked(isExactlyOnce: isExactlyOnce, state: state)
      return (state.isClosed || state.renewalsStopped, target)
    }
    if shouldStop {
      for item in items {
        item.leaseTracker.markExpired()
      }
      return []
    }

    var survivingItems = items
    if isExactlyOnce {
      let survivingIDs = await self.sendReceiptModAckWithEODRetry(
        items: items,
        deadlineSeconds: targetSeconds
      )
      survivingItems = items.filter { survivingIDs.contains($0.ackID) }
    }

    return self.enrollSurvivingItems(
      survivingItems,
      isExactlyOnce: isExactlyOnce,
      targetSeconds: targetSeconds
    )
  }

  package func registerNonEODBatchSync(_ items: [IncomingLeaseItem]) -> [IncomingLeaseItem] {
    self.enrollSurvivingItems(items, isExactlyOnce: false, targetSeconds: 0)
  }

  private func enrollSurvivingItems(
    _ items: [IncomingLeaseItem],
    isExactlyOnce: Bool,
    targetSeconds: Int32
  ) -> [IncomingLeaseItem] {
    guard !items.isEmpty else { return [] }

    let now = self.clock.now
    let canRenew = self.subscribeOptions.maxExtension > .zero
    var expiredImmediately: [LeaseTracker] = []
    var enrolled: [IncomingLeaseItem] = []
    var scheduledEarliest: ContinuousClock.Instant?

    self.state.withLock { state in
      if state.isClosed || state.renewalsStopped {
        for item in items {
          expiredImmediately.append(item.leaseTracker)
        }
        return
      }
      state.sessionExactlyOnce = isExactlyOnce

      if !canRenew {
        // When maxExtension <= 0, deliver without enrolling renewal so leases expire immediately
        // without issuing ModAck(0) if left unsettled past expiry (`LEASE-03`).
        for item in items {
          expiredImmediately.append(item.leaseTracker)
        }
        enrolled = items
        return
      }

      let maxDeadline = now + self.subscribeOptions.maxExtension
      let nextRenewal: ContinuousClock.Instant
      if isExactlyOnce {
        nextRenewal = min(now + Self.renewalDelay(forSeconds: targetSeconds), maxDeadline)
      } else {
        // Non-EOD schedules background initial ModAck without gating delivery,
        // satisfying LEASE-02/03/04 timing while avoiding spurious ModAcks during fast acking.
        nextRenewal = min(now + self.initialNonEODGrace, maxDeadline)
      }

      for item in items {
        if var existing = state.activeLeases[item.ackID] {
          existing.maxDeadline = max(existing.maxDeadline, maxDeadline)
          existing.nextRenewalAt = min(existing.nextRenewalAt, nextRenewal)
          existing.leaseTrackers.append(WeakLeaseTrackerRef(value: item.leaseTracker))
          existing.isPendingAck = false
          state.activeLeases[item.ackID] = existing
        } else {
          state.activeLeases[item.ackID] = ActiveLease(
            ackID: item.ackID,
            receivedAt: now,
            maxDeadline: maxDeadline,
            leaseTrackers: [WeakLeaseTrackerRef(value: item.leaseTracker)],
            nextRenewalAt: nextRenewal,
            isExactlyOnce: isExactlyOnce
          )
        }
      }
      enrolled = items
      scheduledEarliest = min(nextRenewal, maxDeadline)
    }

    for tracker in expiredImmediately {
      tracker.markExpired()
    }
    if let scheduledEarliest {
      self.wakeOrStartRenewalLoop(earliestDeadline: scheduledEarliest)
    }
    return enrolled
  }

  package func cancelRenewals() {
    let (renewalTask, cancelSleep) = self.state.withLock {
      state -> (Task<Void, Never>?, (@Sendable () -> Void)?) in
      state.renewalsStopped = true
      let task = state.renewalTask
      let sleepCancel = state.renewalSleepCancelBox
      state.renewalTask = nil
      state.renewalSleepCancelBox = nil
      return (task, sleepCancel)
    }
    cancelSleep?()
    renewalTask?.cancel()
  }

  package func waitForActiveLeasesToSettle(timeout: Duration?) async -> Bool {
    await self.flushQueuedSettlementsNow()

    let alreadySettled = self.state.withLock { state in
      state.activeLeases.isEmpty && state.inFlightSettlementRPCs == 0 && state.pendingAcks.isEmpty
        && state.pendingNacks.isEmpty
    }
    if alreadySettled {
      return true
    }

    let waiterID = self.state.withLock { state -> UInt64 in
      let id = state.nextWaiterID
      state.nextWaiterID += 1
      return id
    }

    @Sendable func waitForIdleOrCancel() async -> Bool {
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          enum ImmediateWait {
            case settled
            case cancelled
            case queued
          }
          let immediate: ImmediateWait = self.state.withLock { state in
            if state.activeLeases.isEmpty && state.inFlightSettlementRPCs == 0
              && state.pendingAcks.isEmpty && state.pendingNacks.isEmpty
            {
              return .settled
            }
            if Task.isCancelled {
              return .cancelled
            }
            state.idleWaiters.append(IdleWaiter(id: waiterID, continuation: continuation))
            return .queued
          }
          switch immediate {
          case .settled:
            continuation.resume(returning: true)
          case .cancelled:
            continuation.resume(returning: false)
          case .queued:
            break
          }
        }
      } onCancel: {
        let cont = self.state.withLock { state -> CheckedContinuation<Bool, Never>? in
          guard let idx = state.idleWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return nil
          }
          return state.idleWaiters.remove(at: idx).continuation
        }
        cont?.resume(returning: false)
      }
    }

    if let timeout {
      if timeout <= .zero {
        return false
      }
      enum WaitOutcome {
        case settled(Bool)
        case timedOut
      }
      let outcome = await withTaskGroup(of: WaitOutcome.self) { group in
        group.addTask {
          .settled(await waitForIdleOrCancel())
        }
        group.addTask {
          try? await self.clock.sleep(for: timeout)
          return .timedOut
        }
        let first = await group.next() ?? .settled(false)
        group.cancelAll()
        return first
      }
      switch outcome {
      case .settled(let didSettle):
        return didSettle
      case .timedOut:
        return false
      }
    }

    return await waitForIdleOrCancel()
  }

  package func bulkNackRemainingAndClose(
    additionalAckIDs: [String] = [],
    timeout: Duration?
  ) async {
    self.cancelRenewals()

    let (remainingLeases, ackTimer, nackTimer):
      ([ActiveLease], Task<Void, Never>?, Task<Void, Never>?) = self.state.withLock {
        state in
        state.isClosed = true
        let active = Array(state.activeLeases.values)
        state.activeLeases.removeAll()
        let at = state.ackTimerTask
        let nt = state.nackTimerTask
        state.ackTimerTask = nil
        state.nackTimerTask = nil
        return (active, at, nt)
      }
    ackTimer?.cancel()
    nackTimer?.cancel()

    await self.flushQueuedSettlementsNow()

    var idsToNack: [String] = remainingLeases.filter { !$0.isPendingAck }.map(\.ackID)
    var seen = Set(idsToNack)
    for id in additionalAckIDs where !seen.contains(id) {
      seen.insert(id)
      idsToNack.append(id)
    }

    if !idsToNack.isEmpty {
      let chunks = self.chunkAckIDs(idsToNack, isModAck: true)
      await withTaskGroup(of: Void.self) { group in
        for chunk in chunks {
          group.addTask {
            var reqOptions = self.subscribeOptions.request
            if let timeout {
              reqOptions.attemptTimeout =
                reqOptions.attemptTimeout.map { min($0, timeout) } ?? timeout
            }
            let req = Google_Pubsub_V1_ModifyAckDeadlineRequest.with {
              $0.subscription = self.subscription
              $0.ackIds = chunk
              $0.ackDeadlineSeconds = 0
            }
            let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]
            do {
              let _: Google_Protobuf_Empty = try await self.pool.unary(
                descriptor: PubSubGRPCDescriptors.modifyAckDeadline,
                request: req,
                options: reqOptions,
                routingParams: routing
              )
            } catch {
              self.pool.pubSubLogger.logTerminalError(
                error,
                method: .modifyAckDeadline,
                resource: self.subscription,
                operation: "shutdownBulkNack"
              )
            }
          }
        }
      }
    }

    for lease in remainingLeases where !lease.isPendingAck {
      for ref in lease.leaseTrackers {
        _ = ref.value?.markSettled()
      }
    }
    self.notifyIdleWaitersIfEmpty()
  }

  private func targetDeadlineSecondsLocked(isExactlyOnce: Bool, state: State) -> Int32 {
    let minSeconds: Int32
    if let configuredMin = self.subscribeOptions.minAckExtension {
      minSeconds = Self.clampedSeconds(configuredMin)
    } else {
      minSeconds = isExactlyOnce ? Self.minEODExtensionSeconds : Self.minExtensionSeconds
    }
    let configuredMax = Self.clampedSeconds(self.subscribeOptions.maxAckExtension)
    let maxSeconds = max(minSeconds, configuredMax)

    if !self.subscribeOptions.enableAdaptiveAckExtension {
      let desired = Self.clampedSeconds(self.subscribeOptions.streamAckDeadline)
      return min(max(desired, minSeconds), maxSeconds)
    }
    if state.ackLatenciesSeconds.isEmpty {
      return minSeconds
    }
    let sorted = state.ackLatenciesSeconds.sorted()
    let idx = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.99))
    return min(max(sorted[idx], minSeconds), maxSeconds)
  }

  private static func clampedSeconds(_ duration: Duration) -> Int32 {
    let comps = duration.components
    var secs = comps.seconds
    if comps.attoseconds > 0 {
      secs += 1
    }
    if secs < Int64(Self.minExtensionSeconds) {
      return Self.minExtensionSeconds
    }
    if secs > Int64(Self.maxExtensionSeconds) {
      return Self.maxExtensionSeconds
    }
    return Int32(secs)
  }

  private static func renewalDelay(forSeconds seconds: Int32) -> Duration {
    let secs = Double(max(Self.minExtensionSeconds, seconds))
    // Keep periodic renewal snappy for short leases (e.g. 10s -> 5s, 60s -> 50s).
    let delaySeconds = max(1.0, min(secs - 2.0, secs * 0.5))
    return .milliseconds(Int64((delaySeconds * 1_000.0).rounded()))
  }

  private func wakeOrStartRenewalLoop(earliestDeadline: ContinuousClock.Instant? = nil) {
    let (cancelOldSleep, taskToStart): ((@Sendable () -> Void)?, Bool) = self.state.withLock {
      state in
      guard !state.renewalsStopped && !state.isClosed && !state.activeLeases.isEmpty else {
        return (nil, false)
      }
      if state.renewalTask != nil,
        let earliest = earliestDeadline,
        let scheduled = state.scheduledWakeAt,
        earliest >= scheduled
      {
        return (nil, false)
      }
      state.scheduledWakeAt = nil
      state.renewalWakeGeneration += 1
      let oldCancel = state.renewalSleepCancelBox
      state.renewalSleepCancelBox = nil
      if state.renewalTask == nil {
        return (oldCancel, true)
      }
      return (oldCancel, false)
    }
    cancelOldSleep?()
    if taskToStart {
      let task = Task<Void, Never> { [weak self] in
        guard let self else { return }
        await self.runRenewalLoop()
      }
      let shouldCancel = self.state.withLock { state -> Bool in
        if state.renewalsStopped || state.isClosed {
          return true
        }
        state.renewalTask = task
        return false
      }
      if shouldCancel {
        task.cancel()
      }
    }
  }

  private func runRenewalLoop() async {
    while !Task.isCancelled {
      enum Action {
        case stop
        case sleepUntil(Duration, UInt64)
        case expire([ActiveLease])
        case renew([String], Int32, Bool)
      }

      let now = self.clock.now
      let action: Action = self.state.withLock { state in
        guard !state.renewalsStopped && !state.isClosed && !state.activeLeases.isEmpty else {
          state.scheduledWakeAt = nil
          state.renewalTask = nil
          return .stop
        }

        var expired: [ActiveLease] = []
        var pendingAckExpiredIDs: [String] = []
        var dueIDs: [String] = []
        var anyExactlyOnce = state.sessionExactlyOnce
        var nextWake: ContinuousClock.Instant?

        for lease in state.activeLeases.values {
          if lease.maxDeadline <= now {
            if lease.isPendingAck {
              pendingAckExpiredIDs.append(lease.ackID)
            } else {
              expired.append(lease)
            }
            continue
          }
          if lease.nextRenewalAt <= now {
            dueIDs.append(lease.ackID)
            if lease.isExactlyOnce {
              anyExactlyOnce = true
            }
          } else {
            let candidate = min(lease.nextRenewalAt, lease.maxDeadline)
            nextWake = nextWake.map { min($0, candidate) } ?? candidate
          }
        }

        for id in pendingAckExpiredIDs {
          state.activeLeases.removeValue(forKey: id)
        }
        for lease in expired {
          state.activeLeases.removeValue(forKey: lease.ackID)
        }
        if !expired.isEmpty {
          state.scheduledWakeAt = nil
          return .expire(expired)
        }
        if !dueIDs.isEmpty {
          state.scheduledWakeAt = nil
          let targetSeconds = self.targetDeadlineSecondsLocked(
            isExactlyOnce: anyExactlyOnce,
            state: state
          )
          let nextAt = now + Self.renewalDelay(forSeconds: targetSeconds)
          for id in dueIDs {
            if var lease = state.activeLeases[id] {
              lease.nextRenewalAt = min(nextAt, lease.maxDeadline)
              state.activeLeases[id] = lease
            }
          }
          return .renew(dueIDs, targetSeconds, anyExactlyOnce)
        }

        if let nextWake {
          state.scheduledWakeAt = nextWake
          let expectedWakeGen = state.renewalWakeGeneration
          let delay = nextWake - now
          return .sleepUntil(max(.milliseconds(1), delay), expectedWakeGen)
        }
        state.scheduledWakeAt = nil
        state.renewalTask = nil
        return .stop
      }

      switch action {
      case .stop:
        self.notifyIdleWaitersIfEmpty()
        return

      case .expire(let expired):
        for lease in expired {
          for ref in lease.leaseTrackers {
            ref.value?.markExpired()
          }
        }
        self.notifyIdleWaitersIfEmpty()

      case .renew(let dueIDs, let deadlineSeconds, let isExactlyOnce):
        await self.sendRenewalModAckChunks(
          ackIDs: dueIDs,
          deadlineSeconds: deadlineSeconds,
          isExactlyOnce: isExactlyOnce
        )

      case .sleepUntil(let duration, let expectedWakeGen):
        final class SleepGateBox: Sendable {
          struct SleepGate: Sendable {
            var continuation: CheckedContinuation<Void, Never>?
            var triggered: Bool = false
          }
          let state = Mutex(SleepGate())
        }
        let gate = SleepGateBox()
        let triggerGate: @Sendable () -> Void = {
          let cont = gate.state.withLock { state -> CheckedContinuation<Void, Never>? in
            if state.triggered {
              return nil
            }
            state.triggered = true
            let c = state.continuation
            state.continuation = nil
            return c
          }
          cont?.resume()
        }
        let abortedBeforeSleep = self.state.withLock { state -> Bool in
          if state.renewalsStopped || state.isClosed || state.activeLeases.isEmpty
            || state.renewalWakeGeneration != expectedWakeGen
          {
            return true
          }
          state.renewalSleepCancelBox = triggerGate
          return false
        }
        if abortedBeforeSleep {
          continue
        }
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            try? await self.clock.sleep(for: duration)
          }
          group.addTask {
            await withTaskCancellationHandler {
              await withCheckedContinuation { continuation in
                let shouldResumeNow = self.state.withLock { state -> Bool in
                  if state.renewalsStopped || state.isClosed
                    || state.renewalWakeGeneration != expectedWakeGen
                  {
                    return true
                  }
                  return gate.state.withLock { g in
                    if g.triggered || Task.isCancelled {
                      g.triggered = true
                      return true
                    }
                    g.continuation = continuation
                    return false
                  }
                }
                if shouldResumeNow {
                  continuation.resume()
                }
              }
            } onCancel: {
              triggerGate()
            }
          }
          _ = await group.next()
          group.cancelAll()
        }
        self.state.withLock { state in
          state.renewalSleepCancelBox = nil
          if state.renewalWakeGeneration == expectedWakeGen {
            state.scheduledWakeAt = nil
          }
        }
        triggerGate()
      }
    }
  }

  private func sendReceiptModAckWithEODRetry(
    items: [IncomingLeaseItem],
    deadlineSeconds: Int32
  ) async -> Set<String> {
    var seenIDs: Set<String> = []
    let uniqueAckIDs = items.compactMap { seenIDs.insert($0.ackID).inserted ? $0.ackID : nil }
    let chunks = self.chunkAckIDs(uniqueAckIDs, isModAck: true)
    let itemsByID = Dictionary(grouping: items, by: \.ackID)
    final class SurvivorsBox: Sendable {
      let set = Mutex<Set<String>>([])
    }
    let survivors = SurvivorsBox()

    await withTaskGroup(of: Void.self) { group in
      for chunk in chunks {
        group.addTask {
          let retryPolicy =
            self.subscribeOptions.request.retryPolicy ?? PubSubRetryPolicy.defaultPublishPolicy
          let backoffPolicy =
            self.subscribeOptions.request.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy
          let clockStart = self.clock.now
          var attemptCount = 0
          var pending = chunk

          func expireItems(for ids: [String]) {
            for id in ids {
              for item in itemsByID[id] ?? [] {
                item.leaseTracker.markExpired()
              }
            }
          }

          while !pending.isEmpty && !Task.isCancelled {
            let stopRequested = self.state.withLock { $0.renewalsStopped || $0.isClosed }
            if stopRequested { break }
            attemptCount += 1
            let req = Google_Pubsub_V1_ModifyAckDeadlineRequest.with {
              $0.subscription = self.subscription
              $0.ackIds = pending
              $0.ackDeadlineSeconds = deadlineSeconds
            }
            let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]
            do {
              let _: Google_Protobuf_Empty = try await self.pool.unary(
                descriptor: PubSubGRPCDescriptors.modifyAckDeadline,
                request: req,
                options: self.subscribeOptions.request,
                routingParams: routing
              )
              survivors.set.withLock { set in
                for id in pending { set.insert(id) }
              }
              break
            } catch let error as RequestError {
              let metadata = Self.extractPubSubErrorInfoMetadata(from: error)
              if !metadata.isEmpty {
                var nextPending: [String] = []
                for id in pending {
                  guard let reason = metadata[id] else {
                    survivors.set.withLock { _ = $0.insert(id) }
                    continue
                  }
                  if reason.hasPrefix("TRANSIENT_FAILURE_") {
                    nextPending.append(id)
                  } else {
                    expireItems(for: [id])
                  }
                }
                pending = nextPending
                if pending.isEmpty { break }
                let state = RetryState(
                  start: ContinuousClock.now - (self.clock.now - clockStart),
                  attemptCount: attemptCount
                )
                let delay = backoffPolicy.backoffDelay(for: state)
                if let remaining = retryPolicy.remainingTime(state: state),
                  remaining <= .zero || delay >= remaining
                {
                  expireItems(for: pending)
                  break
                }
                try? await self.clock.sleep(for: delay)
                continue
              }

              let state = RetryState(
                start: ContinuousClock.now - (self.clock.now - clockStart),
                attemptCount: attemptCount
              )
              if case .retry = retryPolicy.onError(state: state, error: error) {
                let delay = backoffPolicy.backoffDelay(for: state)
                if let remaining = retryPolicy.remainingTime(state: state),
                  remaining <= .zero || delay >= remaining
                {
                  expireItems(for: pending)
                  break
                }
                try? await self.clock.sleep(for: delay)
                continue
              } else {
                expireItems(for: pending)
                break
              }
            } catch {
              expireItems(for: pending)
              break
            }
          }
        }
      }
    }

    return survivors.set.withLock { $0 }
  }

  private func sendRenewalModAckChunks(
    ackIDs: [String],
    deadlineSeconds: Int32,
    isExactlyOnce: Bool
  ) async {
    let chunks = self.chunkAckIDs(ackIDs, isModAck: true)
    let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]

    for chunk in chunks {
      let stopped = self.state.withLock { $0.renewalsStopped || $0.isClosed }
      if stopped { return }

      var pending = chunk
      var attemptCount = 0
      let clockStart = self.clock.now
      let retryPolicy =
        self.subscribeOptions.request.retryPolicy ?? PubSubRetryPolicy.defaultPublishPolicy
      let backoffPolicy =
        self.subscribeOptions.request.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy

      while !pending.isEmpty && !Task.isCancelled {
        let shouldAbort = self.state.withLock { $0.renewalsStopped || $0.isClosed }
        if shouldAbort { return }
        attemptCount += 1

        let req = Google_Pubsub_V1_ModifyAckDeadlineRequest.with {
          $0.subscription = self.subscription
          $0.ackIds = pending
          $0.ackDeadlineSeconds = deadlineSeconds
        }
        do {
          let _: Google_Protobuf_Empty = try await self.pool.unary(
            descriptor: PubSubGRPCDescriptors.modifyAckDeadline,
            request: req,
            options: self.subscribeOptions.request,
            routingParams: routing
          )
          break
        } catch let error as RequestError {
          if !isExactlyOnce {
            // `LEASE-04`: at-least-once ModAck errors never crash the stream.
            self.pool.pubSubLogger.logRPCDebug(
              "Ignoring non-fatal at-least-once ModifyAckDeadline renewal failure",
              method: .modifyAckDeadline,
              resource: self.subscription,
              extraMetadata: ["error": .string("\(error)")]
            )
            break
          }

          let metadata = Self.extractPubSubErrorInfoMetadata(from: error)
          if !metadata.isEmpty {
            var nextPending: [String] = []
            for id in pending {
              guard let reason = metadata[id] else {
                continue
              }
              if reason.hasPrefix("TRANSIENT_FAILURE_") {
                nextPending.append(id)
              } else {
                // Permanently failed lease renewal stops renewing that ID (`EOD-03b`).
                let (removed, cancelSleep): (ActiveLease?, (@Sendable () -> Void)?) =
                  self.state.withLock { state in
                    let rem = state.activeLeases.removeValue(forKey: id)
                    let cancel = state.activeLeases.isEmpty ? state.renewalSleepCancelBox : nil
                    if state.activeLeases.isEmpty {
                      state.renewalSleepCancelBox = nil
                    }
                    return (rem, cancel)
                  }
                cancelSleep?()
                if let removed, !removed.isPendingAck {
                  for ref in removed.leaseTrackers {
                    ref.value?.markExpired()
                  }
                }
              }
            }
            pending = nextPending
            if pending.isEmpty { break }
            let state = RetryState(
              start: ContinuousClock.now - (self.clock.now - clockStart),
              attemptCount: attemptCount
            )
            let delay = backoffPolicy.backoffDelay(for: state)
            if let remaining = retryPolicy.remainingTime(state: state),
              remaining <= .zero || delay >= remaining
            {
              break
            }
            try? await self.clock.sleep(for: delay)
            continue
          }

          let state = RetryState(
            start: ContinuousClock.now - (self.clock.now - clockStart),
            attemptCount: attemptCount
          )
          if case .retry = retryPolicy.onError(state: state, error: error) {
            let delay = backoffPolicy.backoffDelay(for: state)
            if let remaining = retryPolicy.remainingTime(state: state),
              remaining <= .zero || delay >= remaining
            {
              break
            }
            try? await self.clock.sleep(for: delay)
            continue
          }
          break
        } catch {
          break
        }
      }
    }
  }

  private func enqueueSettlement(
    ackID: String,
    kind: SettlementKind,
    isExactlyOnce: Bool,
    requestOptions: RequestOptions,
    continuation: CheckedContinuation<AckResult, any Error>?
  ) {
    let now = self.clock.now
    let item = SettlementRequest(
      ackID: ackID,
      isExactlyOnce: isExactlyOnce,
      requestOptions: requestOptions,
      continuation: continuation
    )

    enum DrainAction {
      case startTimer(SettlementKind)
      case flushImmediately(SettlementKind, [SettlementRequest], Task<Void, Never>?)
      case buffered
    }

    let (action, cancelSleep): (DrainAction, (@Sendable () -> Void)?) = self.state.withLock {
      state in
      if kind == .ack && isExactlyOnce {
        if var lease = state.activeLeases[ackID] {
          if !lease.isPendingAck {
            Self.recordAckLatencyLocked(receivedAt: lease.receivedAt, now: now, in: &state)
            lease.isPendingAck = true
            lease.maxDeadline = max(lease.maxDeadline, lease.receivedAt + .seconds(600))
            state.activeLeases[ackID] = lease
          }
        }
      } else if let removed = state.activeLeases.removeValue(forKey: ackID), kind == .ack {
        Self.recordAckLatencyLocked(receivedAt: removed.receivedAt, now: now, in: &state)
      }

      var sleepToCancel: (@Sendable () -> Void)? = nil
      if state.activeLeases.isEmpty {
        sleepToCancel = state.renewalSleepCancelBox
        state.renewalSleepCancelBox = nil
      }

      switch kind {
      case .ack:
        state.pendingAcks.append(item)
        if state.pendingAcks.count >= Self.maxAckIDsPerRequest {
          let batch = state.pendingAcks
          state.pendingAcks.removeAll(keepingCapacity: true)
          let timer = state.ackTimerTask
          state.ackTimerTask = nil
          state.inFlightSettlementRPCs += 1
          return (.flushImmediately(.ack, batch, timer), sleepToCancel)
        }
        return (state.ackTimerTask == nil ? .startTimer(.ack) : .buffered, sleepToCancel)

      case .nack:
        state.pendingNacks.append(item)
        if state.pendingNacks.count >= Self.maxAckIDsPerRequest {
          let batch = state.pendingNacks
          state.pendingNacks.removeAll(keepingCapacity: true)
          let timer = state.nackTimerTask
          state.nackTimerTask = nil
          state.inFlightSettlementRPCs += 1
          return (.flushImmediately(.nack, batch, timer), sleepToCancel)
        }
        return (state.nackTimerTask == nil ? .startTimer(.nack) : .buffered, sleepToCancel)
      }
    }
    cancelSleep?()

    switch action {
    case .buffered:
      break
    case .startTimer(let targetKind):
      let task = Task<Void, Never> {
        do {
          try await self.clock.sleep(for: Self.coalesceWindow)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        await self.flushPendingQueue(kind: targetKind, cancelExistingTimer: false)
      }
      self.state.withLock { state in
        switch targetKind {
        case .ack:
          if state.ackTimerTask == nil && !state.pendingAcks.isEmpty {
            state.ackTimerTask = task
          } else {
            task.cancel()
          }
        case .nack:
          if state.nackTimerTask == nil && !state.pendingNacks.isEmpty {
            state.nackTimerTask = task
          } else {
            task.cancel()
          }
        }
      }
    case .flushImmediately(let targetKind, let batch, let timer):
      timer?.cancel()
      Task {
        await self.dispatchSettlementBatch(
          kind: targetKind, items: batch, countAlreadyTracked: true)
      }
    }
  }

  private func flushQueuedSettlementsNow() async {
    async let flushA: Void = self.flushPendingQueue(kind: .ack, cancelExistingTimer: true)
    async let flushN: Void = self.flushPendingQueue(kind: .nack, cancelExistingTimer: true)
    _ = await (flushA, flushN)
  }

  private func flushPendingQueue(kind: SettlementKind, cancelExistingTimer: Bool) async {
    let (batch, timer): ([SettlementRequest], Task<Void, Never>?) = self.state.withLock {
      state in
      switch kind {
      case .ack:
        let b = state.pendingAcks
        state.pendingAcks.removeAll(keepingCapacity: true)
        let t = state.ackTimerTask
        state.ackTimerTask = nil
        if !b.isEmpty {
          state.inFlightSettlementRPCs += 1
        }
        return (b, t)
      case .nack:
        let b = state.pendingNacks
        state.pendingNacks.removeAll(keepingCapacity: true)
        let t = state.nackTimerTask
        state.nackTimerTask = nil
        if !b.isEmpty {
          state.inFlightSettlementRPCs += 1
        }
        return (b, t)
      }
    }
    if cancelExistingTimer {
      timer?.cancel()
    }
    guard !batch.isEmpty else { return }
    await self.dispatchSettlementBatch(kind: kind, items: batch, countAlreadyTracked: true)
  }

  private func dispatchSettlementBatch(
    kind: SettlementKind,
    items: [SettlementRequest],
    countAlreadyTracked: Bool
  ) async {
    defer {
      if countAlreadyTracked {
        self.state.withLock { state in
          state.inFlightSettlementRPCs = max(0, state.inFlightSettlementRPCs - 1)
        }
        self.notifyIdleWaitersIfEmpty()
      }
    }

    let atLeastOnce = items.filter { !$0.isExactlyOnce }
    let exactlyOnce = items.filter(\.isExactlyOnce)

    await withTaskGroup(of: Void.self) { group in
      if !atLeastOnce.isEmpty {
        let chunks = self.chunkSettlementRequests(atLeastOnce, isModAck: kind == .nack)
        for chunk in chunks {
          group.addTask {
            await self.sendAtLeastOnceChunk(kind: kind, items: chunk)
          }
        }
      }
      if !exactlyOnce.isEmpty {
        let chunks = self.chunkSettlementRequests(exactlyOnce, isModAck: kind == .nack)
        for chunk in chunks {
          group.addTask {
            await self.sendExactlyOnceChunk(kind: kind, items: chunk)
          }
        }
      }
    }
  }

  private func sendAtLeastOnceChunk(kind: SettlementKind, items: [SettlementRequest]) async {
    var mergedOptions = self.subscribeOptions.request
    for item in items where !GRPCChannelPool.isEmptyRequestOptions(item.requestOptions) {
      mergedOptions = GRPCChannelPool.mergeRequestOptions(
        base: mergedOptions,
        override: item.requestOptions
      )
    }
    let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]
    do {
      switch kind {
      case .ack:
        let req = Google_Pubsub_V1_AcknowledgeRequest.with {
          $0.subscription = self.subscription
          $0.ackIds = items.map(\.ackID)
        }
        let _: Google_Protobuf_Empty = try await self.pool.unary(
          descriptor: PubSubGRPCDescriptors.acknowledge,
          request: req,
          options: mergedOptions,
          routingParams: routing
        )
      case .nack:
        let req = Google_Pubsub_V1_ModifyAckDeadlineRequest.with {
          $0.subscription = self.subscription
          $0.ackIds = items.map(\.ackID)
          $0.ackDeadlineSeconds = 0
        }
        let _: Google_Protobuf_Empty = try await self.pool.unary(
          descriptor: PubSubGRPCDescriptors.modifyAckDeadline,
          request: req,
          options: mergedOptions,
          routingParams: routing
        )
      }
    } catch {
      // `LEASE-04` & `EOD-02`: when isExactlyOnce is false, ignore errors and resolve `.success`.
      self.pool.pubSubLogger.logRPCDebug(
        "Ignoring at-least-once settlement failure",
        method: kind == .ack ? .acknowledge : .modifyAckDeadline,
        resource: self.subscription,
        extraMetadata: ["error": .string("\(error)")]
      )
    }
    for item in items {
      item.continuation?.resume(returning: AckResult(status: .success))
    }
  }

  private static func recordAckLatencyLocked(
    receivedAt: ContinuousClock.Instant,
    now: ContinuousClock.Instant,
    in state: inout State
  ) {
    let elapsedComps = (now - receivedAt).components
    let elapsedSeconds = Int32(
      min(Int64(Self.maxExtensionSeconds), max(1, elapsedComps.seconds)))
    if state.ackLatenciesSeconds.count >= Self.maxLatencySamples {
      _ = state.ackLatenciesSeconds.popFirst()
    }
    state.ackLatenciesSeconds.append(elapsedSeconds)
  }

  private func finishPendingExactlyOnceAcks(_ ackIDs: [String]) {
    guard !ackIDs.isEmpty else { return }
    let cancelSleep = self.state.withLock { state -> (@Sendable () -> Void)? in
      for ackID in ackIDs where state.activeLeases[ackID]?.isPendingAck == true {
        state.activeLeases.removeValue(forKey: ackID)
      }
      if state.activeLeases.isEmpty {
        let cancel = state.renewalSleepCancelBox
        state.renewalSleepCancelBox = nil
        return cancel
      }
      return nil
    }
    cancelSleep?()
    self.notifyIdleWaitersIfEmpty()
  }

  private func sendExactlyOnceChunk(kind: SettlementKind, items: [SettlementRequest]) async {
    var mergedOptions = self.subscribeOptions.request
    for item in items where !GRPCChannelPool.isEmptyRequestOptions(item.requestOptions) {
      mergedOptions = GRPCChannelPool.mergeRequestOptions(
        base: mergedOptions,
        override: item.requestOptions
      )
    }
    let retryPolicy = mergedOptions.retryPolicy ?? PubSubRetryPolicy.defaultPublishPolicy
    let backoffPolicy = mergedOptions.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy
    let throttler = mergedOptions.retryThrottler ?? self.pool.defaultRetryThrottler
    let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]
    let method: PubSubRPCMethod = kind == .ack ? .acknowledge : .modifyAckDeadline
    let operation = kind == .ack ? "acknowledge" : "nack"
    let descriptor =
      kind == .ack ? PubSubGRPCDescriptors.acknowledge : PubSubGRPCDescriptors.modifyAckDeadline

    let clockStart = self.clock.now
    var attemptCount = 0
    var pending = items
    defer {
      if kind == .ack && !pending.isEmpty {
        self.finishPendingExactlyOnceAcks(pending.map(\.ackID))
      }
    }

    while !pending.isEmpty {
      attemptCount += 1
      let state = RetryState(
        start: ContinuousClock.now - (self.clock.now - clockStart),
        attemptCount: attemptCount
      )
      var attemptOptions = mergedOptions
      if let remaining = retryPolicy.remainingTime(state: state) {
        if attemptCount > 1 && remaining <= .zero {
          let err = PubSubError.settlementFailed(
            AckError(
              status: .other("DEADLINE_EXCEEDED"), message: "Settlement retry budget exhausted")
          )
          self.pool.pubSubLogger.logTerminalError(
            err, method: method, resource: self.subscription, operation: operation)
          for item in pending { item.continuation?.resume(throwing: err) }
          return
        }
        attemptOptions.attemptTimeout =
          attemptOptions.attemptTimeout.map { min($0, remaining) } ?? remaining
      }

      if attemptCount > 1 && throttler.throttleRetryAttempt() {
        let placeholder = RequestError.service(
          ServiceError(code: .unavailable, message: "Settlement throttled", details: [])
        )
        switch retryPolicy.onThrottle(state: state, error: placeholder) {
        case .exhausted:
          self.pool.pubSubLogger.logTerminalError(
            placeholder, method: method, resource: self.subscription, operation: operation)
          let ackErr = Self.mapRequestErrorToAckError(placeholder)
          for item in pending {
            item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
          }
          return
        case .retry:
          let delay = backoffPolicy.backoffDelay(for: state)
          if let remaining = retryPolicy.remainingTime(state: state),
            remaining <= .zero || delay >= remaining
          {
            self.pool.pubSubLogger.logTerminalError(
              placeholder, method: method, resource: self.subscription, operation: operation)
            let ackErr = Self.mapRequestErrorToAckError(placeholder)
            for item in pending {
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
            return
          }
          try? await self.clock.sleep(for: delay)
          continue
        @unknown default:
          break
        }
      }

      do {
        switch kind {
        case .ack:
          let req = Google_Pubsub_V1_AcknowledgeRequest.with {
            $0.subscription = self.subscription
            $0.ackIds = pending.map(\.ackID)
          }
          let _: Google_Protobuf_Empty = try await self.pool.unary(
            descriptor: descriptor,
            request: req,
            options: attemptOptions,
            routingParams: routing
          )
        case .nack:
          let req = Google_Pubsub_V1_ModifyAckDeadlineRequest.with {
            $0.subscription = self.subscription
            $0.ackIds = pending.map(\.ackID)
            $0.ackDeadlineSeconds = 0
          }
          let _: Google_Protobuf_Empty = try await self.pool.unary(
            descriptor: descriptor,
            request: req,
            options: attemptOptions,
            routingParams: routing
          )
        }
        throttler.onSuccess()
        for item in pending {
          item.continuation?.resume(returning: AckResult(status: .success))
        }
        if kind == .ack {
          self.finishPendingExactlyOnceAcks(pending.map(\.ackID))
        }
        pending.removeAll()
        return
      } catch let requestError as RequestError {
        let errorMetadata = Self.extractPubSubErrorInfoMetadata(from: requestError)
        if !errorMetadata.isEmpty {
          var nextPending: [SettlementRequest] = []
          var finishedIDs: [String] = []
          var hasPermanentError = false
          for item in pending {
            guard let reason = errorMetadata[item.ackID] else {
              // Absent from ErrorInfo metadata -> succeeded cleanly in this batch (`EOD-03b`).
              finishedIDs.append(item.ackID)
              item.continuation?.resume(returning: AckResult(status: .success))
              continue
            }
            if reason.hasPrefix("TRANSIENT_FAILURE_") {
              nextPending.append(item)
            } else {
              hasPermanentError = true
              finishedIDs.append(item.ackID)
              let ackErr = Self.mapReasonToAckError(reason, underlying: requestError)
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
          }
          if hasPermanentError {
            self.pool.pubSubLogger.logTerminalError(
              requestError, method: method, resource: self.subscription, operation: operation)
          }
          if kind == .ack {
            self.finishPendingExactlyOnceAcks(finishedIDs)
          }
          pending = nextPending
          if pending.isEmpty {
            return
          }
          let evalState = RetryState(
            start: ContinuousClock.now - (self.clock.now - clockStart),
            attemptCount: attemptCount
          )
          throttler.onRetryFailure(.retry(requestError))
          let delay = backoffPolicy.backoffDelay(for: evalState)
          if let remaining = retryPolicy.remainingTime(state: evalState),
            remaining <= .zero || delay >= remaining
          {
            self.pool.pubSubLogger.logTerminalError(
              requestError, method: method, resource: self.subscription, operation: operation)
            for item in pending {
              let reason = errorMetadata[item.ackID] ?? "TRANSIENT_FAILURE"
              let ackErr = Self.mapReasonToAckError(reason, underlying: requestError)
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
            return
          }
          do {
            try await self.clock.sleep(for: delay)
          } catch {
            self.pool.pubSubLogger.logTerminalError(
              error, method: method, resource: self.subscription, operation: operation)
            for item in pending {
              let reason = errorMetadata[item.ackID] ?? "TRANSIENT_FAILURE"
              let ackErr = Self.mapReasonToAckError(reason, underlying: requestError)
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
            return
          }
          continue
        }

        let evalState = RetryState(
          start: ContinuousClock.now - (self.clock.now - clockStart),
          attemptCount: attemptCount
        )
        switch retryPolicy.onError(state: evalState, error: requestError) {
        case .permanent, .exhausted:
          throttler.onRetryFailure(.permanent(requestError))
          self.pool.pubSubLogger.logTerminalError(
            requestError,
            method: method,
            resource: self.subscription,
            operation: operation
          )
          let ackErr = Self.mapRequestErrorToAckError(requestError)
          for item in pending {
            item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
          }
          return

        case .retry:
          throttler.onRetryFailure(.retry(requestError))
          let delay = backoffPolicy.backoffDelay(for: evalState)
          if let remaining = retryPolicy.remainingTime(state: evalState),
            remaining <= .zero || delay >= remaining
          {
            self.pool.pubSubLogger.logTerminalError(
              requestError, method: method, resource: self.subscription, operation: operation)
            let ackErr = Self.mapRequestErrorToAckError(requestError)
            for item in pending {
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
            return
          }
          do {
            try await self.clock.sleep(for: delay)
          } catch {
            self.pool.pubSubLogger.logTerminalError(
              error, method: method, resource: self.subscription, operation: operation)
            let ackErr = Self.mapRequestErrorToAckError(requestError)
            for item in pending {
              item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
            }
            return
          }

        @unknown default:
          self.pool.pubSubLogger.logTerminalError(
            requestError, method: method, resource: self.subscription, operation: operation)
          let ackErr = Self.mapRequestErrorToAckError(requestError)
          for item in pending {
            item.continuation?.resume(throwing: PubSubError.settlementFailed(ackErr))
          }
          return
        }
      } catch {
        self.pool.pubSubLogger.logTerminalError(
          error, method: method, resource: self.subscription, operation: operation)
        for item in pending {
          item.continuation?.resume(throwing: error)
        }
        return
      }
    }
  }

  private func notifyIdleWaitersIfEmpty() {
    let waitersToResume: [CheckedContinuation<Bool, Never>] = self.state.withLock { state in
      guard
        state.activeLeases.isEmpty && state.inFlightSettlementRPCs == 0
          && state.pendingAcks.isEmpty && state.pendingNacks.isEmpty
      else {
        return []
      }
      let conts = state.idleWaiters.map(\.continuation)
      state.idleWaiters.removeAll()
      return conts
    }
    for cont in waitersToResume {
      cont.resume(returning: true)
    }
  }

  private func chunkSettlementRequests(
    _ requests: [SettlementRequest],
    isModAck: Bool
  ) -> [[SettlementRequest]] {
    self.chunkItems(requests, ackID: \.ackID, isModAck: isModAck)
  }

  private func chunkAckIDs(_ ackIDs: [String], isModAck: Bool) -> [[String]] {
    self.chunkItems(ackIDs, ackID: { $0 }, isModAck: isModAck)
  }

  private func chunkItems<Element>(
    _ items: [Element],
    ackID: (Element) -> String,
    isModAck: Bool
  ) -> [[Element]] {
    guard !items.isEmpty else { return [] }
    let baseOverhead = self.subscriptionOverheadBytes + (isModAck ? 12 : 4)
    var chunks: [[Element]] = []
    var current: [Element] = []
    var currentBytes = baseOverhead

    for item in items {
      let idUTF8Count = ackID(item).utf8.count
      let entryBytes = 1 + Self.varintSize(idUTF8Count) + idUTF8Count
      if !current.isEmpty
        && (current.count + 1 > Self.maxAckIDsPerRequest
          || currentBytes + entryBytes > Self.maxRequestBytes)
      {
        chunks.append(current)
        current = []
        currentBytes = baseOverhead
      }
      current.append(item)
      currentBytes += entryBytes
    }
    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks
  }

  private static func extractPubSubErrorInfoMetadata(from error: RequestError) -> [String: String] {
    guard case .service(let svc) = error else { return [:] }
    var merged: [String: String] = [:]
    for detail in svc.details {
      if case .errorInfo(let info) = detail, info.domain == "pubsub.googleapis.com" {
        for (k, v) in info.metadata {
          merged[k] = v
        }
      }
    }
    return merged
  }

  private static func mapReasonToAckError(_ reason: String, underlying: RequestError) -> AckError {
    let status: SettlementStatus
    switch reason {
    case "PERMANENT_FAILURE_INVALID_ACK_ID":
      status = .invalidAckID
    case "PERMANENT_FAILURE_PERMISSION_DENIED":
      status = .permissionDenied
    case "PERMANENT_FAILURE_FAILED_PRECONDITION":
      status = .failedPrecondition
    default:
      status = .other(reason)
    }
    return AckError(status: status, message: reason, underlyingError: underlying)
  }

  private static func mapRequestErrorToAckError(_ error: RequestError) -> AckError {
    guard case .service(let svc) = error else {
      return AckError(status: .other("\(error)"), message: "\(error)", underlyingError: error)
    }
    let status: SettlementStatus
    switch svc.code {
    case .permissionDenied:
      status = .permissionDenied
    case .failedPrecondition:
      status = .failedPrecondition
    default:
      status = .other(svc.code.stringValue ?? "\(svc.code)")
    }
    return AckError(status: status, message: svc.message, underlyingError: error)
  }

  private static func varintSize(_ value: Int) -> Int {
    var v = UInt64(max(0, value))
    var bytes = 1
    while v >= 0x80 {
      v >>= 7
      bytes += 1
    }
    return bytes
  }
}
