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
import GoogleWKT
import Logging
import Synchronization
import _GoogleCloudPubSubProtos
import SwiftProtobuf

package final class TopicBatchPublisher: Sendable {
  private static let maxBatchMessagesLimit = 1_000
  private static let maxPublishRequestBytes = 10_000_000

  private struct OpenBatch: Sendable {
    let id: UInt64
    let orderingKey: String
    let resultBox: BatchPublishBox
    var messageProtos: [Google_Pubsub_V1_PubsubMessage]
    var messageWireBytesSum: Int
    var requestWireBytes: Int
    var totalPermitMessages: Int
    var totalPermitBytes: Int
    var customRequestOptions: [RequestOptions]
    var timerTask: Task<Void, Never>?
  }

  private struct SealedBatch: Sendable {
    let id: UInt64
    let orderingKey: String
    let resultBox: BatchPublishBox
    let messageProtos: [Google_Pubsub_V1_PubsubMessage]
    let requestWireBytes: Int
    let totalPermitMessages: Int
    let totalPermitBytes: Int
    let customRequestOptions: [RequestOptions]
  }

  private static func makeSealedBatch(from openBatch: OpenBatch) -> SealedBatch {
    SealedBatch(
      id: openBatch.id,
      orderingKey: openBatch.orderingKey,
      resultBox: openBatch.resultBox,
      messageProtos: openBatch.messageProtos,
      requestWireBytes: openBatch.requestWireBytes,
      totalPermitMessages: openBatch.totalPermitMessages,
      totalPermitBytes: openBatch.totalPermitBytes,
      customRequestOptions: openBatch.customRequestOptions
    )
  }

  private struct KeyLane: Sendable {
    var isPaused: Bool = false
    var openBatch: OpenBatch? = nil
    var sealedQueue: Deque<SealedBatch> = []
    var inFlightCount: Int = 0

    var hasPendingWork: Bool {
      self.openBatch != nil || !self.sealedQueue.isEmpty || self.inFlightCount > 0
    }
  }

  private struct FlushBarrier: Sendable {
    let id: UInt64
    var pendingBatchIDs: Set<UInt64>
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct State: Sendable {
    var isShutDown: Bool = false
    var nextBatchID: UInt64 = 1
    var nextBarrierID: UInt64 = 1
    var nextSubchannelRoundRobin: Int = 0
    var lanes: [String: KeyLane] = [:]
    var activeBatchIDs: Set<UInt64> = []
    var activeTasks: [UInt64: Task<Void, Never>] = [:]
    var flushBarriers: [FlushBarrier] = []
  }

  private let resolvedTopic: String
  private let options: TopicPublisherOptions
  private let effectiveMaxMessages: Int
  private let effectiveMaxBytes: Int
  private let topicOverheadBytes: Int
  private let pool: GRPCChannelPool
  private let ownsPool: Bool
  private let clock: any PubSubClock
  private let flowController: PublisherFlowController
  private let hedgingBucket: HedgingTokenBucket
  private let state = Mutex(State())

  package init(
    resolvedTopic: String,
    options: TopicPublisherOptions,
    pool: GRPCChannelPool,
    ownsPool: Bool,
    clock: any PubSubClock
  ) {
    self.resolvedTopic = resolvedTopic
    self.options = options
    self.effectiveMaxMessages = min(
      max(options.batching.countThreshold, 1), Self.maxBatchMessagesLimit)
    self.effectiveMaxBytes = min(
      max(options.batching.byteThreshold, 1), Self.maxPublishRequestBytes)
    let topicUTF8Count = resolvedTopic.utf8.count
    self.topicOverheadBytes = 1 + Self.varintSize(topicUTF8Count) + topicUTF8Count
    self.pool = pool
    self.ownsPool = ownsPool
    self.clock = clock
    self.flowController = PublisherFlowController(options.flowControl)
    self.hedgingBucket = HedgingTokenBucket(options.hedging)
  }

  deinit {
    self.forceAbortRemainingWork()
  }

  package func startPublish(_ message: Message, options callOptions: PublishOptions) async throws
    -> PublishHandle
  {
    let preCheckError: PubSubError? = self.state.withLock { state in
      if state.isShutDown {
        return PubSubError.publisherShutDown
      }
      if !message.orderingKey.isEmpty, state.lanes[message.orderingKey]?.isPaused == true {
        return PubSubError.orderingKeyPaused(orderingKey: message.orderingKey)
      }
      return nil
    }
    if let preCheckError {
      throw preCheckError
    }

    let wireBytes = try message.validateForPublish()
    let permit: PublishPermit
    do {
      if let fastPermit = try self.flowController.tryAcquireImmediate(bytes: wireBytes) {
        permit = fastPermit
      } else {
        permit = try await self.flowController.acquire(bytes: wireBytes)
      }
    } catch let fcError as PubSubError {
      if case .flowControlLimitExceeded = fcError, !message.orderingKey.isEmpty {
        self.pauseKeyOnFlowControlRejection(orderingKey: message.orderingKey)
      }
      throw fcError
    }

    let messageProto = message.toProto()
    let entryBytes = 1 + Self.varintSize(wireBytes) + wireBytes
    let hasCustomRequestOptions = !GRPCChannelPool.isEmptyRequestOptions(callOptions.request)

    enum EnqueueOutcome {
      case rejected(PubSubError)
      case accepted(
        dispatches: [SealedBatch],
        timersToCancel: [Task<Void, Never>],
        timerToStart: (orderingKey: String, batchID: UInt64)?,
        resultBox: BatchPublishBox,
        messageIndex: Int
      )
    }

    let orderingKey = message.orderingKey
    let outcome: EnqueueOutcome = self.state.withLock { state in
      if state.isShutDown {
        return .rejected(.publisherShutDown)
      }
      var lane = state.lanes[orderingKey, default: KeyLane()]
      if !orderingKey.isEmpty && lane.isPaused {
        return .rejected(.orderingKeyPaused(orderingKey: orderingKey))
      }

      var dispatches: [SealedBatch] = []
      var timersToCancel: [Task<Void, Never>] = []
      var timerToStart: (orderingKey: String, batchID: UInt64)?
      let assignedBox: BatchPublishBox
      let assignedIndex: Int

      if var openBatch = lane.openBatch {
        let exceedsCount = openBatch.messageProtos.count + 1 > self.effectiveMaxMessages
        let exceedsMsgBytes =
          openBatch.messageWireBytesSum + wireBytes > self.effectiveMaxBytes
        let exceedsRequestBytes =
          openBatch.requestWireBytes + entryBytes > Self.maxPublishRequestBytes
        if !openBatch.messageProtos.isEmpty
          && (exceedsCount || exceedsMsgBytes || exceedsRequestBytes)
        {
          if let timer = openBatch.timerTask {
            timersToCancel.append(timer)
          }
          lane.openBatch = nil
          lane.sealedQueue.append(Self.makeSealedBatch(from: openBatch))
          let batchID = state.nextBatchID
          state.nextBatchID += 1
          let newBox = BatchPublishBox()
          assignedBox = newBox
          assignedIndex = 0
          lane.openBatch = OpenBatch(
            id: batchID,
            orderingKey: orderingKey,
            resultBox: newBox,
            messageProtos: [messageProto],
            messageWireBytesSum: wireBytes,
            requestWireBytes: self.topicOverheadBytes + entryBytes,
            totalPermitMessages: permit.messages,
            totalPermitBytes: permit.bytes,
            customRequestOptions: hasCustomRequestOptions ? [callOptions.request] : [],
            timerTask: nil
          )
        } else {
          assignedBox = openBatch.resultBox
          assignedIndex = openBatch.messageProtos.count
          openBatch.messageProtos.append(messageProto)
          openBatch.messageWireBytesSum += wireBytes
          openBatch.requestWireBytes += entryBytes
          openBatch.totalPermitMessages += permit.messages
          openBatch.totalPermitBytes += permit.bytes
          if hasCustomRequestOptions {
            openBatch.customRequestOptions.append(callOptions.request)
          }
          lane.openBatch = openBatch
        }
      } else {
        let batchID = state.nextBatchID
        state.nextBatchID += 1
        let newBox = BatchPublishBox()
        assignedBox = newBox
        assignedIndex = 0
        lane.openBatch = OpenBatch(
          id: batchID,
          orderingKey: orderingKey,
          resultBox: newBox,
          messageProtos: [messageProto],
          messageWireBytesSum: wireBytes,
          requestWireBytes: self.topicOverheadBytes + entryBytes,
          totalPermitMessages: permit.messages,
          totalPermitBytes: permit.bytes,
          customRequestOptions: hasCustomRequestOptions ? [callOptions.request] : [],
          timerTask: nil
        )
      }

      if let openBatch = lane.openBatch {
        let shouldSealImmediately =
          openBatch.messageProtos.count >= self.effectiveMaxMessages
          || openBatch.messageWireBytesSum >= self.effectiveMaxBytes
          || openBatch.requestWireBytes >= Self.maxPublishRequestBytes
          || self.options.batching.delayThreshold <= .zero
        if shouldSealImmediately {
          if let timer = openBatch.timerTask {
            timersToCancel.append(timer)
          }
          lane.openBatch = nil
          lane.sealedQueue.append(Self.makeSealedBatch(from: openBatch))
        } else if openBatch.messageProtos.count == 1 && openBatch.timerTask == nil {
          timerToStart = (orderingKey: orderingKey, batchID: openBatch.id)
        }
      }

      dispatches = self.popDispatchableLocked(lane: &lane, orderingKey: orderingKey, state: &state)
      state.lanes[orderingKey] = lane
      return .accepted(
        dispatches: dispatches,
        timersToCancel: timersToCancel,
        timerToStart: timerToStart,
        resultBox: assignedBox,
        messageIndex: assignedIndex
      )
    }

    switch outcome {
    case .rejected(let error):
      self.flowController.release(permit)
      throw error

    case .accepted(
      let dispatches, let timersToCancel, let timerToStart, let resultBox, let messageIndex):
      for timer in timersToCancel {
        timer.cancel()
      }
      if let timerSpec = timerToStart {
        let delay = self.options.batching.delayThreshold
        let task = Task { [weak self] in
          try? await self?.clock.sleep(for: delay)
          guard !Task.isCancelled else { return }
          self?.handleDelayTimerFired(
            orderingKey: timerSpec.orderingKey, batchID: timerSpec.batchID)
        }
        let shouldCancelImmediately = self.state.withLock { state -> Bool in
          guard var lane = state.lanes[timerSpec.orderingKey],
            var openBatch = lane.openBatch,
            openBatch.id == timerSpec.batchID
          else {
            return true
          }
          openBatch.timerTask = task
          lane.openBatch = openBatch
          state.lanes[timerSpec.orderingKey] = lane
          return false
        }
        if shouldCancelImmediately {
          task.cancel()
        }
      }
      self.launchDispatches(dispatches)
      return PublishHandle(batchBox: resultBox, index: messageIndex)
    }
  }

  package func flush(options: FlushOptions) async throws -> FlushResult {
    let barrier = self.sealAllAndCollectBarrier()
    guard let barrier else {
      return FlushResult()
    }
    try await self.waitForBarrier(
      barrier, timeout: options.request.attemptTimeout, timeoutLabel: "flush")
    return FlushResult()
  }

  package func resumePublishing(orderingKey: String, options: ResumePublishingOptions) async throws
    -> ResumePublishingResult
  {
    let isShutDown = self.state.withLock { state -> Bool in
      if state.isShutDown {
        return true
      }
      if var lane = state.lanes[orderingKey] {
        lane.isPaused = false
        if !lane.hasPendingWork {
          state.lanes.removeValue(forKey: orderingKey)
        } else {
          state.lanes[orderingKey] = lane
        }
      }
      return false
    }
    if isShutDown {
      throw PubSubError.publisherShutDown
    }
    return ResumePublishingResult()
  }

  package func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    let (alreadyShutDown, barrier) = self.state.withLock {
      state -> (Bool, (id: UInt64, empty: Bool)?) in
      if state.isShutDown {
        return (true, nil)
      }
      state.isShutDown = true
      return (false, nil)
    }
    if alreadyShutDown {
      return ShutdownResult()
    }
    _ = barrier

    var shutdownError: (any Error)?
    if let flushBarrier = self.sealAllAndCollectBarrier() {
      do {
        try await self.waitForBarrier(
          flushBarrier,
          timeout: options.request.attemptTimeout,
          timeoutLabel: "shutdown"
        )
      } catch {
        shutdownError = error
        self.forceAbortRemainingWork()
      }
    }

    if self.ownsPool {
      await self.pool.shutdown()
    }
    if let shutdownError {
      throw shutdownError
    }
    return ShutdownResult()
  }

  private func forceAbortRemainingWork() {
    let (tasksToCancel, drainedPermits, resolvedBarriers):
      ([Task<Void, Never>], [PublishPermit], [CheckedContinuation<Void, Never>]) =
        self.state.withLock { state in
          var tasks: [Task<Void, Never>] = []
          var permits: [PublishPermit] = []
          for (_, task) in state.activeTasks {
            tasks.append(task)
          }
          state.activeBatchIDs.removeAll()
          state.activeTasks.removeAll()
          for (key, var lane) in state.lanes {
            if let openBatch = lane.openBatch {
              if let timer = openBatch.timerTask {
                tasks.append(timer)
              }
              openBatch.resultBox.resolveFailure(PubSubError.publisherShutDown)
              permits.append(
                PublishPermit(
                  messages: openBatch.totalPermitMessages,
                  bytes: openBatch.totalPermitBytes
                )
              )
              lane.openBatch = nil
            }
            while let sealed = lane.sealedQueue.popFirst() {
              sealed.resultBox.resolveFailure(PubSubError.publisherShutDown)
              permits.append(
                PublishPermit(
                  messages: sealed.totalPermitMessages,
                  bytes: sealed.totalPermitBytes
                )
              )
            }
            lane.inFlightCount = 0
            state.lanes[key] = lane
          }
          state.lanes.removeAll()
          let continuations = state.flushBarriers.map(\.continuation)
          state.flushBarriers.removeAll()
          return (tasks, permits, continuations)
        }
    for task in tasksToCancel {
      task.cancel()
    }
    for permit in drainedPermits {
      self.flowController.release(permit)
    }
    for cont in resolvedBarriers {
      cont.resume()
    }
  }

  private func pauseKeyOnFlowControlRejection(orderingKey: String) {
    let (timersToCancel, permitsToRelease, drainedBatchIDs):
      ([Task<Void, Never>], [PublishPermit], [UInt64]) = self.state.withLock { state in
        var lane = state.lanes[orderingKey, default: KeyLane()]
        lane.isPaused = true
        var timers: [Task<Void, Never>] = []
        var permits: [PublishPermit] = []
        var batchIDs: [UInt64] = []
        if let openBatch = lane.openBatch {
          if let timer = openBatch.timerTask {
            timers.append(timer)
          }
          openBatch.resultBox.resolveFailure(
            PubSubError.orderingKeyPaused(orderingKey: orderingKey))
          permits.append(
            PublishPermit(
              messages: openBatch.totalPermitMessages,
              bytes: openBatch.totalPermitBytes
            )
          )
          batchIDs.append(openBatch.id)
          lane.openBatch = nil
        }
        while let sealed = lane.sealedQueue.popFirst() {
          sealed.resultBox.resolveFailure(PubSubError.orderingKeyPaused(orderingKey: orderingKey))
          permits.append(
            PublishPermit(
              messages: sealed.totalPermitMessages,
              bytes: sealed.totalPermitBytes
            )
          )
          batchIDs.append(sealed.id)
        }
        state.lanes[orderingKey] = lane
        return (timers, permits, batchIDs)
      }

    for timer in timersToCancel {
      timer.cancel()
    }
    for permit in permitsToRelease {
      self.flowController.release(permit)
    }
    if !drainedBatchIDs.isEmpty {
      self.markBatchesFinished(batchIDs: drainedBatchIDs)
    }
  }

  private func handleDelayTimerFired(orderingKey: String, batchID: UInt64) {
    let dispatches = self.state.withLock { state -> [SealedBatch] in
      guard var lane = state.lanes[orderingKey],
        let openBatch = lane.openBatch,
        openBatch.id == batchID
      else {
        return []
      }
      let sealed = Self.makeSealedBatch(from: openBatch)
      lane.openBatch = nil
      lane.sealedQueue.append(sealed)
      let ready = self.popDispatchableLocked(lane: &lane, orderingKey: orderingKey, state: &state)
      state.lanes[orderingKey] = lane
      return ready
    }
    self.launchDispatches(dispatches)
  }

  private struct PendingBarrier {
    let barrierID: UInt64
    let pendingIDs: Set<UInt64>
  }

  private func sealAllAndCollectBarrier() -> PendingBarrier? {
    let (dispatches, timersToCancel, pendingBarrier):
      ([SealedBatch], [Task<Void, Never>], PendingBarrier?) = self.state.withLock { state in
        var timers: [Task<Void, Never>] = []
        var dispatches: [SealedBatch] = []
        var activeIDs: Set<UInt64> = state.activeBatchIDs

        for (key, var lane) in state.lanes {
          if let openBatch = lane.openBatch {
            if let timer = openBatch.timerTask {
              timers.append(timer)
            }
            lane.openBatch = nil
            lane.sealedQueue.append(Self.makeSealedBatch(from: openBatch))
          }
          for batch in lane.sealedQueue {
            activeIDs.insert(batch.id)
          }
          let ready = self.popDispatchableLocked(lane: &lane, orderingKey: key, state: &state)
          for batch in ready {
            activeIDs.insert(batch.id)
          }
          dispatches.append(contentsOf: ready)
          state.lanes[key] = lane
        }

        if activeIDs.isEmpty {
          return (dispatches, timers, nil)
        }
        let barrierID = state.nextBarrierID
        state.nextBarrierID += 1
        return (dispatches, timers, PendingBarrier(barrierID: barrierID, pendingIDs: activeIDs))
      }

    for timer in timersToCancel {
      timer.cancel()
    }
    self.launchDispatches(dispatches)
    return pendingBarrier
  }

  private func awaitBarrier(_ pendingBarrier: PendingBarrier) async {
    let barrierID = pendingBarrier.barrierID
    final class BarrierCancelBox: Sendable {
      struct BarrierCancelState: Sendable {
        var registered: Bool = false
        var cancelled: Bool = false
      }
      let state = Mutex(BarrierCancelState())
    }
    let cancelBox = BarrierCancelBox()

    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let alreadyDone = self.state.withLock { state -> Bool in
          let shouldCancel = cancelBox.state.withLock { cs -> Bool in
            if cs.cancelled || Task.isCancelled {
              cs.cancelled = true
              return true
            }
            return false
          }
          if shouldCancel {
            return true
          }
          var remaining: Set<UInt64> = []
          for batchID in pendingBarrier.pendingIDs {
            if state.activeBatchIDs.contains(batchID) {
              remaining.insert(batchID)
              continue
            }
            let inQueue = state.lanes.values.contains { lane in
              lane.sealedQueue.contains { $0.id == batchID }
            }
            if inQueue {
              remaining.insert(batchID)
            }
          }
          if remaining.isEmpty {
            return true
          }
          state.flushBarriers.append(
            FlushBarrier(
              id: barrierID,
              pendingBatchIDs: remaining,
              continuation: continuation
            )
          )
          cancelBox.state.withLock { $0.registered = true }
          return false
        }
        if alreadyDone {
          continuation.resume()
        }
      }
    } onCancel: {
      let shouldRemove = cancelBox.state.withLock { cs -> Bool in
        cs.cancelled = true
        return cs.registered
      }
      if shouldRemove {
        self.removeBarrier(id: barrierID)
      }
    }
  }

  private func waitForBarrier(
    _ pendingBarrier: PendingBarrier,
    timeout: Duration?,
    timeoutLabel: String
  ) async throws {
    if let timeout {
      enum WaitOutcome {
        case drained
        case timedOut
      }
      let outcome = await withTaskGroup(of: WaitOutcome.self) { group in
        group.addTask {
          await self.awaitBarrier(pendingBarrier)
          return .drained
        }
        group.addTask {
          try? await self.clock.sleep(for: timeout)
          return .timedOut
        }
        let first = await group.next() ?? .drained
        group.cancelAll()
        return first
      }
      if outcome == .timedOut {
        self.removeBarrier(id: pendingBarrier.barrierID)
        let underlying = RequestError.service(
          ServiceError(
            code: .deadlineExceeded,
            message: "Publish \(timeoutLabel) timed out after \(timeout).",
            details: []
          )
        )
        throw RequestError.exhausted(
          .elapsedTime(maximumDuration: timeout, underlyingError: underlying)
        )
      }
      try Task.checkCancellation()
    } else {
      await self.awaitBarrier(pendingBarrier)
      try Task.checkCancellation()
    }
  }

  private func removeBarrier(id: UInt64) {
    let cont = self.state.withLock { state -> CheckedContinuation<Void, Never>? in
      guard let idx = state.flushBarriers.firstIndex(where: { $0.id == id }) else {
        return nil
      }
      return state.flushBarriers.remove(at: idx).continuation
    }
    cont?.resume()
  }

  private func popDispatchableLocked(
    lane: inout KeyLane,
    orderingKey: String,
    state: inout State
  ) -> [SealedBatch] {
    if !orderingKey.isEmpty {
      guard lane.inFlightCount == 0, let next = lane.sealedQueue.popFirst() else {
        return []
      }
      lane.inFlightCount = 1
      state.activeBatchIDs.insert(next.id)
      return [next]
    }
    var out: [SealedBatch] = []
    while let next = lane.sealedQueue.popFirst() {
      lane.inFlightCount += 1
      state.activeBatchIDs.insert(next.id)
      out.append(next)
    }
    return out
  }

  private func launchDispatches(_ batches: [SealedBatch]) {
    guard !batches.isEmpty else { return }
    for batch in batches {
      let subchannelIndex = self.nextSubchannelIndex(for: batch.orderingKey)
      let task = Task { [weak self] in
        guard let self else { return }
        await self.executeBatch(batch, baseSubchannelIndex: subchannelIndex)
      }
      let cancelImmediately = self.state.withLock { state -> Bool in
        guard state.activeBatchIDs.contains(batch.id) else {
          return false
        }
        guard !state.isShutDown || !state.lanes.isEmpty else {
          return true
        }
        state.activeTasks[batch.id] = task
        return false
      }
      if cancelImmediately {
        task.cancel()
      }
    }
  }

  private func nextSubchannelIndex(for orderingKey: String) -> Int {
    let count = max(1, self.pool.subchannelCount)
    if !orderingKey.isEmpty {
      var hash: UInt64 = 1_469_598_103_934_665_603
      for byte in orderingKey.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
      }
      return Int(hash % UInt64(count))
    }
    return self.state.withLock { state in
      let idx = state.nextSubchannelRoundRobin % count
      state.nextSubchannelRoundRobin += 1
      return idx
    }
  }

  private func executeBatch(_ batch: SealedBatch, baseSubchannelIndex: Int) async {
    let publishRequest = Google_Pubsub_V1_PublishRequest.with {
      $0.topic = self.resolvedTopic
      $0.messages = batch.messageProtos
    }

    var mergedOptions = self.options.request
    if !batch.customRequestOptions.isEmpty {
      for customOptions in batch.customRequestOptions {
        mergedOptions = GRPCChannelPool.mergeRequestOptions(
          base: mergedOptions, override: customOptions)
      }
    }

    let retryPolicy = mergedOptions.retryPolicy ?? PubSubRetryPolicy.defaultPublishPolicy
    let backoffPolicy = mergedOptions.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy
    let throttler = mergedOptions.retryThrottler ?? self.pool.defaultRetryThrottler
    let routing = [_RoutingMatcher.format(key: "topic", value: self.resolvedTopic)]
    let useGzip =
      self.options.compression.isEnabled
      && batch.requestWireBytes > self.options.compression.bytesThreshold
    let compression: CompressionAlgorithm? = useGzip ? .gzip : nil
    let hedging = self.options.hedging
    let startTimestamp: Google_Protobuf_Timestamp? =
      hedging.isEnabled ? Google_Protobuf_Timestamp(date: Date()) : nil

    self.pool.pubSubLogger.logRPCDebug(
      "Sending batched Publish RPC",
      method: .publish,
      resource: self.resolvedTopic,
      extraMetadata: [
        "pubsub.batch_messages": .stringConvertible(batch.messageProtos.count),
        "pubsub.batch_bytes": .stringConvertible(batch.requestWireBytes),
        "pubsub.ordering_key_present": .stringConvertible(!batch.orderingKey.isEmpty),
        "pubsub.compressed": .stringConvertible(useGzip),
      ]
    )

    do {
      let response: Google_Pubsub_V1_PublishResponse = try await PubSubRetryExecutor.execute(
        retryPolicy: retryPolicy,
        backoffPolicy: backoffPolicy,
        throttler: throttler,
        clock: self.clock
      ) { [mergedOptions, compression, hedging, startTimestamp] remainingTime in
        var attemptOptions = mergedOptions
        if let remainingTime {
          attemptOptions.attemptTimeout =
            attemptOptions.attemptTimeout.map {
              min($0, remainingTime)
            } ?? remainingTime
        }
        return try await self.sendAttemptWithOptionalHedging(
          request: publishRequest,
          orderingKey: batch.orderingKey,
          options: attemptOptions,
          routing: routing,
          compression: compression,
          baseSubchannelIndex: baseSubchannelIndex,
          hedging: hedging,
          startTimestamp: startTimestamp
        )
      }

      guard response.messageIds.count == batch.messageProtos.count else {
        throw PubSubError.mismatchedMessageIDCount(
          expected: batch.messageProtos.count,
          received: response.messageIds.count
        )
      }

      batch.resultBox.resolveSuccess(response.messageIds)

      self.completeBatchSuccess(batch)
    } catch {
      self.pool.pubSubLogger.logTerminalError(
        error,
        method: .publish,
        resource: self.resolvedTopic,
        operation: "batchPublish"
      )
      batch.resultBox.resolveFailure(error)
      self.completeBatchFailure(batch)
    }
  }

  private func sendAttemptWithOptionalHedging(
    request: Google_Pubsub_V1_PublishRequest,
    orderingKey: String,
    options: RequestOptions,
    routing: [String],
    compression: CompressionAlgorithm?,
    baseSubchannelIndex: Int,
    hedging: HedgingOptions,
    startTimestamp: Google_Protobuf_Timestamp?
  ) async throws -> Google_Pubsub_V1_PublishResponse {
    func telemetryHeaders(attemptIndex: Int) -> [(name: String, value: String)] {
      guard let startTimestamp else { return [] }
      var telemetry = Google_Pubsub_V1_PubsubClientTelemetry()
      telemetry.publishOperation.hedgedAttemptCount = Int32(attemptIndex)
      telemetry.publishOperation.publishStartTime = startTimestamp
      let encoded = (try? telemetry.serializedData().base64EncodedString()) ?? ""
      return [("x-goog-pubsub-client-telemetry", encoded)]
    }

    if !hedging.isEnabled {
      return try await self.pool.unary(
        descriptor: PubSubGRPCDescriptors.publish,
        request: request,
        options: options,
        routingParams: routing,
        compression: compression,
        subchannelIndex: baseSubchannelIndex
      )
    }

    // Keyed batches never launch concurrent hedged attempts (`HDG-04`),
    // while still reporting client telemetry with attempt index 0.
    if !orderingKey.isEmpty {
      let response: Google_Pubsub_V1_PublishResponse = try await self.pool.unary(
        descriptor: PubSubGRPCDescriptors.publish,
        request: request,
        options: options,
        routingParams: routing,
        extraHeaders: telemetryHeaders(attemptIndex: 0),
        compression: compression,
        subchannelIndex: baseSubchannelIndex
      )
      self.hedgingBucket.recordSuccess()
      return response
    }

    enum HedgeGroupEvent: Sendable {
      case rpcResult(Result<Google_Pubsub_V1_PublishResponse, any Error>)
      case timerFired(Int)
    }

    return try await withThrowingTaskGroup(of: HedgeGroupEvent.self) { group in
      var inFlightRPCs = 1
      group.addTask {
        do {
          let resp: Google_Pubsub_V1_PublishResponse = try await self.pool.unary(
            descriptor: PubSubGRPCDescriptors.publish,
            request: request,
            options: options,
            routingParams: routing,
            extraHeaders: telemetryHeaders(attemptIndex: 0),
            compression: compression,
            subchannelIndex: baseSubchannelIndex
          )
          return .rpcResult(.success(resp))
        } catch {
          return .rpcResult(.failure(error))
        }
      }

      group.addTask {
        try? await self.clock.sleep(for: hedging.delay)
        return .timerFired(1)
      }

      var lastError: (any Error)?
      while let event = try await group.next() {
        switch event {
        case .rpcResult(.success(let response)):
          self.hedgingBucket.recordSuccess()
          group.cancelAll()
          return response

        case .rpcResult(.failure(let error)):
          inFlightRPCs -= 1
          lastError = error
          if inFlightRPCs == 0 {
            group.cancelAll()
            throw error
          }

        case .timerFired(let attemptIndex):
          guard !Task.isCancelled else { continue }
          guard self.hedgingBucket.tryConsumeHedgeToken() else { continue }
          inFlightRPCs += 1
          let subIdx = baseSubchannelIndex + attemptIndex
          let headers = telemetryHeaders(attemptIndex: attemptIndex)
          group.addTask {
            do {
              let resp: Google_Pubsub_V1_PublishResponse = try await self.pool.unary(
                descriptor: PubSubGRPCDescriptors.publish,
                request: request,
                options: options,
                routingParams: routing,
                extraHeaders: headers,
                compression: compression,
                subchannelIndex: subIdx
              )
              return .rpcResult(.success(resp))
            } catch {
              return .rpcResult(.failure(error))
            }
          }
          group.addTask {
            try? await self.clock.sleep(for: hedging.delay)
            return .timerFired(attemptIndex + 1)
          }
        }
      }
      throw lastError ?? CancellationError()
    }
  }

  private func completeBatchSuccess(_ batch: SealedBatch) {
    let (dispatches, finishedIDs): ([SealedBatch], [UInt64]) = self.state.withLock { state in
      state.activeBatchIDs.remove(batch.id)
      state.activeTasks.removeValue(forKey: batch.id)
      var nextDispatches: [SealedBatch] = []
      if var lane = state.lanes[batch.orderingKey] {
        lane.inFlightCount = max(0, lane.inFlightCount - 1)
        nextDispatches = self.popDispatchableLocked(
          lane: &lane,
          orderingKey: batch.orderingKey,
          state: &state
        )
        if !lane.hasPendingWork && !lane.isPaused {
          state.lanes.removeValue(forKey: batch.orderingKey)
        } else {
          state.lanes[batch.orderingKey] = lane
        }
      }
      return (nextDispatches, [batch.id])
    }
    self.flowController.release(
      PublishPermit(messages: batch.totalPermitMessages, bytes: batch.totalPermitBytes)
    )
    self.launchDispatches(dispatches)
    self.markBatchesFinished(batchIDs: finishedIDs)
  }

  private func completeBatchFailure(_ batch: SealedBatch) {
    let orderingKey = batch.orderingKey
    let (timersToCancel, extraPermits, finishedIDs):
      ([Task<Void, Never>], [PublishPermit], [UInt64]) = self.state.withLock { state in
        state.activeBatchIDs.remove(batch.id)
        state.activeTasks.removeValue(forKey: batch.id)
        var timers: [Task<Void, Never>] = []
        var permits: [PublishPermit] = []
        var finished: [UInt64] = [batch.id]

        if var lane = state.lanes[orderingKey] {
          lane.inFlightCount = max(0, lane.inFlightCount - 1)
          if !orderingKey.isEmpty {
            lane.isPaused = true
            if let openBatch = lane.openBatch {
              if let timer = openBatch.timerTask {
                timers.append(timer)
              }
              openBatch.resultBox.resolveFailure(
                PubSubError.orderingKeyPaused(orderingKey: orderingKey)
              )
              permits.append(
                PublishPermit(
                  messages: openBatch.totalPermitMessages,
                  bytes: openBatch.totalPermitBytes
                )
              )
              finished.append(openBatch.id)
              lane.openBatch = nil
            }
            while let queued = lane.sealedQueue.popFirst() {
              queued.resultBox.resolveFailure(
                PubSubError.orderingKeyPaused(orderingKey: orderingKey)
              )
              permits.append(
                PublishPermit(
                  messages: queued.totalPermitMessages,
                  bytes: queued.totalPermitBytes
                )
              )
              finished.append(queued.id)
            }
          }
          if !lane.hasPendingWork && !lane.isPaused {
            state.lanes.removeValue(forKey: orderingKey)
          } else {
            state.lanes[orderingKey] = lane
          }
        }
        return (timers, permits, finished)
      }

    for timer in timersToCancel {
      timer.cancel()
    }
    self.flowController.release(
      PublishPermit(messages: batch.totalPermitMessages, bytes: batch.totalPermitBytes)
    )
    for permit in extraPermits {
      self.flowController.release(permit)
    }
    self.markBatchesFinished(batchIDs: finishedIDs)
  }

  private func markBatchesFinished(batchIDs: [UInt64]) {
    let continuations = self.state.withLock { state -> [CheckedContinuation<Void, Never>] in
      guard !state.flushBarriers.isEmpty else { return [] }
      var ready: [CheckedContinuation<Void, Never>] = []
      var remainingBarriers: [FlushBarrier] = []
      for var barrier in state.flushBarriers {
        for id in batchIDs {
          barrier.pendingBatchIDs.remove(id)
        }
        if barrier.pendingBatchIDs.isEmpty {
          ready.append(barrier.continuation)
        } else {
          remainingBarriers.append(barrier)
        }
      }
      state.flushBarriers = remainingBarriers
      return ready
    }
    for cont in continuations {
      cont.resume()
    }
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
