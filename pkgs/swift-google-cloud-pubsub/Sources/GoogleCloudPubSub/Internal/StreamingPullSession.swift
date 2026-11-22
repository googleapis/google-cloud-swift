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
import GoogleWKT
@_spi(GoogleCloudInternal) import GoogleWKTConvert
import Logging
import Synchronization
import SwiftProtobuf
import _GoogleCloudPubSubProtos

private final class AtomicFlag: Sendable {
  let value = Atomic(false)
}

package final class SubscriberFlowGate: Sendable {
  private final class Waiter: Sendable {
    enum Outcome: Sendable {
      case pending
      case granted
      case cancelled
    }

    private struct WaiterState: Sendable {
      var outcome: Outcome = .pending
      var continuation: CheckedContinuation<Void, any Error>?
    }

    let id: UInt64
    let bytes: Int
    private let state = Mutex(WaiterState())

    init(id: UInt64, bytes: Int) {
      self.id = id
      self.bytes = bytes
    }

    func attachOrResolve(_ continuation: CheckedContinuation<Void, any Error>) {
      let immediate = self.state.withLock { s -> Outcome? in
        switch s.outcome {
        case .pending:
          s.continuation = continuation
          return nil
        case .granted, .cancelled:
          return s.outcome
        }
      }
      switch immediate {
      case .granted:
        continuation.resume()
      case .cancelled:
        continuation.resume(throwing: CancellationError())
      case .pending, nil:
        break
      }
    }

    func markGrantedAndTakeContinuation() -> CheckedContinuation<Void, any Error>? {
      self.state.withLock { s in
        guard s.outcome == .pending else { return nil }
        s.outcome = .granted
        let c = s.continuation
        s.continuation = nil
        return c
      }
    }

    func markCancelledAndTakeContinuation() -> CheckedContinuation<Void, any Error>? {
      self.state.withLock { s in
        guard s.outcome == .pending else { return nil }
        s.outcome = .cancelled
        let c = s.continuation
        s.continuation = nil
        return c
      }
    }
  }

  private struct State: Sendable {
    var outstandingMessages: Int = 0
    var outstandingBytes: Int = 0
    var nextWaiterID: UInt64 = 1
    var waiters: Deque<Waiter> = []
    var closed: Bool = false
  }

  private let maxMessages: Int
  private let maxBytes: Int
  private let state = Mutex(State())

  init(maxMessages: Int, maxBytes: Int) {
    self.maxMessages = maxMessages
    self.maxBytes = maxBytes
  }

  package func tryAcquirePrefix(count: Int, byteSizeAt: (Int) -> Int) -> Int {
    guard count > 0 else { return 0 }
    return self.state.withLock { state in
      guard !state.closed, state.waiters.isEmpty else {
        return 0
      }
      var admitted = 0
      while admitted < count {
        let bytes = byteSizeAt(admitted)
        guard self.canAdmitLocked(bytes: bytes, state: state) else {
          break
        }
        state.outstandingMessages += 1
        state.outstandingBytes += bytes
        admitted += 1
      }
      return admitted
    }
  }

  func acquire(bytes: Int) async throws {
    try Task.checkCancellation()
    enum Outcome {
      case granted
      case wait(Waiter)
      case closed
    }

    let outcome: Outcome = self.state.withLock { state in
      if state.closed {
        return .closed
      }
      if state.waiters.isEmpty && self.canAdmitLocked(bytes: bytes, state: state) {
        state.outstandingMessages += 1
        state.outstandingBytes += bytes
        return .granted
      }
      let id = state.nextWaiterID
      state.nextWaiterID += 1
      let waiter = Waiter(id: id, bytes: bytes)
      state.waiters.append(waiter)
      return .wait(waiter)
    }

    switch outcome {
    case .granted:
      return
    case .closed:
      throw CancellationError()
    case .wait(let waiter):
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          if Task.isCancelled && self.removeWaiter(id: waiter.id) {
            _ = waiter.markCancelledAndTakeContinuation()
            continuation.resume(throwing: CancellationError())
            self.wakeReadyWaiters()
          } else {
            waiter.attachOrResolve(continuation)
          }
        }
      } onCancel: {
        if self.removeWaiter(id: waiter.id),
          let cont = waiter.markCancelledAndTakeContinuation()
        {
          cont.resume(throwing: CancellationError())
        }
        self.wakeReadyWaiters()
      }
    }
  }

  package func release(bytes: Int) {
    let toWake = self.state.withLock { state -> [CheckedContinuation<Void, any Error>] in
      state.outstandingMessages = max(0, state.outstandingMessages - 1)
      state.outstandingBytes = max(0, state.outstandingBytes - bytes)
      return self.popReadyLocked(state: &state)
    }
    for cont in toWake {
      cont.resume()
    }
  }

  func closeAll() {
    let toCancel = self.state.withLock { state -> [CheckedContinuation<Void, any Error>] in
      state.closed = true
      var conts: [CheckedContinuation<Void, any Error>] = []
      while let waiter = state.waiters.popFirst() {
        if let cont = waiter.markCancelledAndTakeContinuation() {
          conts.append(cont)
        }
      }
      return conts
    }
    for cont in toCancel {
      cont.resume(throwing: CancellationError())
    }
  }

  private func removeWaiter(id: UInt64) -> Bool {
    self.state.withLock { state in
      let before = state.waiters.count
      state.waiters.removeAll { $0.id == id }
      return state.waiters.count < before
    }
  }

  private func wakeReadyWaiters() {
    let toWake = self.state.withLock { state in
      self.popReadyLocked(state: &state)
    }
    for cont in toWake {
      cont.resume()
    }
  }

  private func popReadyLocked(state: inout State) -> [CheckedContinuation<Void, any Error>] {
    guard !state.closed else { return [] }
    var out: [CheckedContinuation<Void, any Error>] = []
    while let head = state.waiters.first {
      guard self.canAdmitLocked(bytes: head.bytes, state: state) else {
        break
      }
      state.waiters.removeFirst()
      state.outstandingMessages += 1
      state.outstandingBytes += head.bytes
      if let cont = head.markGrantedAndTakeContinuation() {
        out.append(cont)
      }
    }
    return out
  }

  private func canAdmitLocked(bytes: Int, state: State) -> Bool {
    if state.outstandingMessages == 0 && state.outstandingBytes == 0 {
      return self.maxMessages >= 1
    }
    return state.outstandingMessages + 1 <= self.maxMessages
      && state.outstandingBytes + bytes <= self.maxBytes
  }
}

package final class StreamingPullSession: Sendable {
  private struct PongTimeoutError: Error {}

  private struct PendingBatch: Sendable {
    let protos: [Google_Pubsub_V1_ReceivedMessage]
    let isExactlyOnce: Bool
    let gate: SubscriberFlowGate
  }

  private struct NextWaiter: Sendable {
    let id: UInt64
    let continuation: CheckedContinuation<ReceivedMessage?, any Error>
  }

  private struct ShutdownWaiter: Sendable {
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct State: Sendable {
    var sessionExactlyOnce: Bool = false
    var stopInitiated: Bool = false
    var shutdownComplete: Bool = false
    var shutdownError: (any Error)? = nil
    var terminalError: (any Error)? = nil

    var workerTasks: [Task<Void, Never>] = []
    var shutdownWaiters: [ShutdownWaiter] = []
    var pendingRawAckIDs: [String: Int] = [:]
    var readyQueue: Deque<(ackID: String, message: ReceivedMessage)> = []
    var nextWaiterID: UInt64 = 1
    var nextWaiters: [NextWaiter] = []
  }

  private let subscription: String
  private let options: SubscribeOptions
  private let pool: GRPCChannelPool
  private let clock: any PubSubClock
  private let leaseManager: LeaseManager
  private let gates: [SubscriberFlowGate]
  private let onFinished: (@Sendable () -> Void)?
  private let state = Mutex(State())

  package init(
    subscription: String,
    options: SubscribeOptions,
    pool: GRPCChannelPool,
    clock: any PubSubClock,
    onFinished: (@Sendable () -> Void)? = nil
  ) {
    self.subscription = subscription
    self.options = options
    self.pool = pool
    self.clock = clock
    self.onFinished = onFinished
    self.leaseManager = LeaseManager(
      subscription: subscription,
      subscribeOptions: options,
      pool: pool,
      clock: clock
    )
    if options.enablePerStreamFlowControl {
      self.gates = (0..<options.streamCount).map { _ in
        SubscriberFlowGate(
          maxMessages: options.maxOutstandingMessages,
          maxBytes: options.maxOutstandingBytes
        )
      }
    } else {
      let shared = SubscriberFlowGate(
        maxMessages: options.maxOutstandingMessages,
        maxBytes: options.maxOutstandingBytes
      )
      self.gates = Array(repeating: shared, count: options.streamCount)
    }
  }

  deinit {
    let tasks = self.state.withLock { state -> [Task<Void, Never>] in
      state.stopInitiated = true
      let out = state.workerTasks
      state.workerTasks.removeAll()
      return out
    }
    for task in tasks {
      task.cancel()
    }
    self.leaseManager.cancelRenewals()
    for gate in self.gates {
      gate.closeAll()
    }
  }

  package func makeMessageStream() -> MessageStream {
    self.startWorkers()
    return MessageStream(session: self)
  }

  private func startWorkers() {
    let streamCount = self.options.streamCount
    var tasks: [Task<Void, Never>] = []
    tasks.reserveCapacity(streamCount)
    for index in 0..<streamCount {
      let clientID = self.options.clientID ?? UUID().uuidString
      let gate = self.gates[index]
      let task = Task<Void, Never> { [weak self] in
        await self?.runStreamWorker(streamIndex: index, clientID: clientID, gate: gate)
      }
      tasks.append(task)
    }

    let cancelImmediately = self.state.withLock { state -> Bool in
      if state.stopInitiated || state.terminalError != nil {
        return true
      }
      state.workerTasks = tasks
      return false
    }
    if cancelImmediately {
      for task in tasks {
        task.cancel()
      }
    }
  }

  package func nextMessage() async throws -> ReceivedMessage? {
    try Task.checkCancellation()
    enum FastPath {
      case message(ReceivedMessage)
      case eof
      case failure(any Error)
      case wait
    }
    let fast: FastPath = self.state.withLock { state in
      if let entry = state.readyQueue.popFirst() {
        return .message(entry.message)
      }
      if let error = state.terminalError {
        return .failure(error)
      }
      if state.stopInitiated {
        return .eof
      }
      return .wait
    }
    switch fast {
    case .message(let msg):
      return msg
    case .eof:
      return nil
    case .failure(let error):
      throw error
    case .wait:
      break
    }

    final class CancelBox: Sendable {
      struct CancelState: Sendable {
        var id: UInt64?
        var cancelled: Bool = false
      }
      let state = Mutex(CancelState())
    }
    let cancelBox = CancelBox()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<ReceivedMessage?, any Error>) in
        enum Immediate {
          case message(ReceivedMessage)
          case eof
          case failure(any Error)
          case wait
        }
        let immediate: Immediate = self.state.withLock { state in
          if let entry = state.readyQueue.popFirst() {
            return .message(entry.message)
          }
          if let error = state.terminalError {
            return .failure(error)
          }
          if state.stopInitiated {
            return .eof
          }
          let id = state.nextWaiterID
          let shouldCancel = cancelBox.state.withLock { cs -> Bool in
            if cs.cancelled || Task.isCancelled {
              cs.cancelled = true
              return true
            }
            cs.id = id
            return false
          }
          if shouldCancel {
            return .failure(CancellationError())
          }
          state.nextWaiterID += 1
          state.nextWaiters.append(NextWaiter(id: id, continuation: continuation))
          return .wait
        }

        switch immediate {
        case .message(let msg):
          continuation.resume(returning: msg)
        case .eof:
          continuation.resume(returning: nil)
        case .failure(let error):
          continuation.resume(throwing: error)
        case .wait:
          break
        }
      }
    } onCancel: {
      let id = cancelBox.state.withLock { cs -> UInt64? in
        cs.cancelled = true
        return cs.id
      }
      guard let id else {
        return
      }
      let cont = self.state.withLock {
        state -> CheckedContinuation<ReceivedMessage?, any Error>? in
        guard let idx = state.nextWaiters.firstIndex(where: { $0.id == id }) else {
          return nil
        }
        return state.nextWaiters.remove(at: idx).continuation
      }
      cont?.resume(throwing: CancellationError())
    }
  }

  package func stop(options shutdownOptions: SubscriberShutdownOptions) async throws
    -> ShutdownResult
  {
    enum StopRole {
      case alreadyComplete((any Error)?)
      case joinInProgress
      case leader(
        tasks: [Task<Void, Never>],
        waiters: [NextWaiter],
        drainedReady: [(ackID: String, message: ReceivedMessage)],
        unDispatchedIDs: [String]
      )
    }

    let role: StopRole = self.state.withLock { state in
      if state.shutdownComplete {
        return .alreadyComplete(state.shutdownError)
      }
      if state.stopInitiated {
        return .joinInProgress
      }
      state.stopInitiated = true
      let tasks = state.workerTasks
      state.workerTasks.removeAll()
      let waiters = state.nextWaiters
      state.nextWaiters.removeAll()
      let drainedReady = Array(state.readyQueue)
      state.readyQueue.removeAll()
      let queued = drainedReady.map(\.ackID)
      let unDispatched = Array(state.pendingRawAckIDs.keys) + queued
      state.pendingRawAckIDs.removeAll()
      return .leader(
        tasks: tasks,
        waiters: waiters,
        drainedReady: drainedReady,
        unDispatchedIDs: unDispatched
      )
    }

    switch role {
    case .alreadyComplete(let err):
      if let err { throw err }
      return ShutdownResult()

    case .joinInProgress:
      await withCheckedContinuation { continuation in
        let alreadyDone = self.state.withLock { state -> Bool in
          if state.shutdownComplete { return true }
          state.shutdownWaiters.append(ShutdownWaiter(continuation: continuation))
          return false
        }
        if alreadyDone {
          continuation.resume()
        }
      }
      let err = self.state.withLock { $0.shutdownError }
      if let err { throw err }
      return ShutdownResult()

    case .leader(let tasks, let waiters, let drainedReady, let unDispatchedIDs):
      // Release permits and suppress ARC deinit nacks outside state lock; unDispatchedIDs bulk-nacks once.
      for entry in drainedReady {
        entry.message.cancelAutoNackAndRelease()
      }
      for waiter in waiters {
        waiter.continuation.resume(returning: nil)
      }
      for gate in self.gates {
        gate.closeAll()
      }
      for task in tasks {
        task.cancel()
      }

      let behavior = shutdownOptions.behavior ?? self.options.defaultShutdownBehavior
      let timeout = shutdownOptions.timeout ?? self.options.defaultShutdownTimeout

      switch behavior {
      case .nackImmediately:
        // Halt lease renewals immediately before draining (`LIFE-02`).
        self.leaseManager.cancelRenewals()
        await self.leaseManager.bulkNackRemainingAndClose(
          additionalAckIDs: unDispatchedIDs,
          timeout: timeout
        )

      case .waitForProcessing:
        let start = self.clock.now
        let settled = await self.leaseManager.waitForActiveLeasesToSettle(timeout: timeout)
        let remainingTimeout: Duration?
        if let timeout {
          let elapsed = self.clock.now - start
          remainingTimeout = elapsed < timeout ? (timeout - elapsed) : .milliseconds(500)
        } else {
          remainingTimeout = nil
        }
        self.leaseManager.cancelRenewals()
        if !settled || !unDispatchedIDs.isEmpty {
          await self.leaseManager.bulkNackRemainingAndClose(
            additionalAckIDs: unDispatchedIDs,
            timeout: remainingTimeout
          )
        } else {
          await self.leaseManager.bulkNackRemainingAndClose(
            additionalAckIDs: [],
            timeout: remainingTimeout
          )
        }

      @unknown default:
        self.leaseManager.cancelRenewals()
        await self.leaseManager.bulkNackRemainingAndClose(
          additionalAckIDs: unDispatchedIDs,
          timeout: timeout
        )
      }

      let shutdownWaiters = self.state.withLock { state -> [ShutdownWaiter] in
        state.shutdownComplete = true
        let out = state.shutdownWaiters
        state.shutdownWaiters.removeAll()
        return out
      }
      for w in shutdownWaiters {
        w.continuation.resume()
      }
      self.onFinished?()
      return ShutdownResult()
    }
  }

  private func runStreamWorker(
    streamIndex: Int,
    clientID: String,
    gate: SubscriberFlowGate
  ) async {
    let retryPolicy = self.options.request.retryPolicy ?? PubSubRetryPolicy.defaultPublishPolicy
    let backoffPolicy = self.options.request.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy
    let throttler = self.options.request.retryThrottler ?? self.pool.defaultRetryThrottler
    var attemptCount = 0
    var clockStart = self.clock.now

    while !Task.isCancelled {
      let stopped = self.state.withLock { $0.stopInitiated || $0.terminalError != nil }
      if stopped { return }

      let receivedAnyFrameBox = AtomicFlag()
      do {
        try await self.runSingleStreamAttempt(
          streamIndex: streamIndex,
          clientID: clientID,
          gate: gate,
          receivedAnyResponse: receivedAnyFrameBox
        )
        throttler.onSuccess()
        attemptCount = 0
        clockStart = self.clock.now
      } catch is CancellationError {
        return
      } catch is PongTimeoutError {
        // Pong timeout transparently recycles the stream with immediate reopen (`PULL-03`).
        attemptCount = 0
        clockStart = self.clock.now
        continue
      } catch {
        let stoppedNow = self.state.withLock { $0.stopInitiated || $0.terminalError != nil }
        if stoppedNow { return }

        if receivedAnyFrameBox.value.load(ordering: .acquiring) {
          attemptCount = 0
          clockStart = self.clock.now
        }
        attemptCount += 1
        let requestError = (error as? GoogleGax.RequestError) ?? .io(error)
        let evalState = RetryState(
          start: ContinuousClock.now - (self.clock.now - clockStart),
          attemptCount: attemptCount
        )

        switch retryPolicy.onError(state: evalState, error: requestError) {
        case .permanent, .exhausted:
          throttler.onRetryFailure(.permanent(requestError))
          self.failStreamSession(with: requestError)
          return

        case .retry:
          throttler.onRetryFailure(.retry(requestError))
          let delay = backoffPolicy.backoffDelay(for: evalState)
          do {
            try await self.clock.sleep(for: delay)
          } catch {
            return
          }

        @unknown default:
          self.failStreamSession(with: requestError)
          return
        }
      }
    }
  }

  private func failStreamSession(with error: RequestError) {
    self.pool.pubSubLogger.logTerminalError(
      error,
      method: .streamingPull,
      resource: self.subscription,
      operation: "streamingPull"
    )
    let (waitersToFail, tasksToCancel) = self.state.withLock {
      state -> ([NextWaiter], [Task<Void, Never>]) in
      if state.terminalError != nil || state.stopInitiated {
        return ([], [])
      }
      state.terminalError = error
      let waiters = state.nextWaiters
      state.nextWaiters.removeAll()
      let tasks = state.workerTasks
      state.workerTasks.removeAll()
      return (waiters, tasks)
    }
    for waiter in waitersToFail {
      waiter.continuation.resume(throwing: error)
    }
    for task in tasksToCancel {
      task.cancel()
    }
  }

  private func runSingleStreamAttempt(
    streamIndex: Int,
    clientID: String,
    gate: SubscriberFlowGate,
    receivedAnyResponse: AtomicFlag
  ) async throws {
    let routing = [_RoutingMatcher.format(key: "subscription", value: self.subscription)]
    let deadlineSeconds = Self.clampedDeadlineSeconds(self.options.streamAckDeadline)

    let frame0 = Google_Pubsub_V1_StreamingPullRequest.with {
      $0.subscription = self.subscription
      $0.clientID = clientID
      $0.streamAckDeadlineSeconds = deadlineSeconds
      $0.protocolVersion = 1
      if self.options.enablePerStreamFlowControl || self.options.maxOutstandingMessages > 0 {
        $0.maxOutstandingMessages = Int64(self.options.maxOutstandingMessages)
      }
      if self.options.enablePerStreamFlowControl || self.options.maxOutstandingBytes > 0 {
        $0.maxOutstandingBytes = Int64(self.options.maxOutstandingBytes)
      }
    }

    let outbound = AsyncStream.makeStream(of: Google_Pubsub_V1_StreamingPullRequest.self)
    let batchQueue = AsyncStream.makeStream(of: PendingBatch.self)
    let frame0Written = AsyncStream.makeStream(of: Void.self)
    let pongTimedOut = AsyncStream.makeStream(of: Void.self)

    final class PongWatchdogState: Sendable {
      private struct S: Sendable {
        var awaitingPong = false
        var generation: UInt64 = 0
        var watchdogTask: Task<Void, Never>?
      }
      private let box = Mutex(S())
      let onTimeout: @Sendable () -> Void

      init(onTimeout: @escaping @Sendable () -> Void) {
        self.onTimeout = onTimeout
      }

      func markPingSent(clock: any PubSubClock, timeout: Duration) {
        let shouldArm = self.box.withLock { s -> UInt64? in
          if s.awaitingPong { return nil }
          s.awaitingPong = true
          s.generation += 1
          return s.generation
        }
        guard let gen = shouldArm else { return }
        let task = Task<Void, Never> { [weak self] in
          do {
            try await clock.sleep(for: timeout)
          } catch {
            return
          }
          guard let self, !Task.isCancelled else { return }
          let fire = self.box.withLock { s -> Bool in
            s.awaitingPong && s.generation == gen
          }
          if fire {
            self.onTimeout()
          }
        }
        self.box.withLock { s in
          if s.awaitingPong && s.generation == gen {
            s.watchdogTask = task
          } else {
            task.cancel()
          }
        }
      }

      func markResponseReceived() {
        let taskToCancel = self.box.withLock { s -> Task<Void, Never>? in
          s.awaitingPong = false
          s.generation += 1
          let t = s.watchdogTask
          s.watchdogTask = nil
          return t
        }
        taskToCancel?.cancel()
      }

      func cancelAll() {
        let taskToCancel = self.box.withLock { s -> Task<Void, Never>? in
          s.awaitingPong = false
          s.generation += 1
          let t = s.watchdogTask
          s.watchdogTask = nil
          return t
        }
        taskToCancel?.cancel()
      }
    }

    // Track whether pong timeout aborted this attempt.
    let timedOutBox = AtomicFlag()
    let watchdog = PongWatchdogState {
      timedOutBox.value.store(true, ordering: .releasing)
      pongTimedOut.continuation.yield(())
      pongTimedOut.continuation.finish()
    }

    let keepaliveTask = Task<Void, Never> { [self] in
      var sentFrame0 = false
      for await _ in frame0Written.stream {
        sentFrame0 = true
        break
      }
      guard sentFrame0 && !Task.isCancelled else { return }
      while !Task.isCancelled {
        do {
          try await self.clock.sleep(for: self.options.keepalivePingInterval)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        watchdog.markPingSent(clock: self.clock, timeout: self.options.keepalivePongTimeout)
        outbound.continuation.yield(Google_Pubsub_V1_StreamingPullRequest())
      }
    }

    defer {
      keepaliveTask.cancel()
      watchdog.cancelAll()
      outbound.continuation.finish()
      batchQueue.continuation.finish()
      frame0Written.continuation.finish()
      pongTimedOut.continuation.finish()
    }

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { [self] in
          try await self.pool.bidirectionalStreaming(
            descriptor: PubSubGRPCDescriptors.streamingPull,
            subchannelIndex: streamIndex,
            options: self.options.request,
            routingParams: routing,
            producer: { writer in
              try await writer.write(frame0)
              frame0Written.continuation.yield(())
              frame0Written.continuation.finish()
              for await frame in outbound.stream {
                try await writer.write(frame)
              }
            },
            onResponse: {
              [self]
              (response: StreamingClientResponse<Google_Pubsub_V1_StreamingPullResponse>) in
              switch response.accepted {
              case .failure(let rpcError):
                throw GRPCChannelPool.convertRPCError(rpcError)

              case .success(let contents):
                let deliveryTask = Task<Void, Never> {
                  for await batch in batchQueue.stream {
                    if Task.isCancelled { break }
                    await self.admitAndDeliverBatch(
                      protos: batch.protos,
                      isExactlyOnce: batch.isExactlyOnce,
                      gate: batch.gate
                    )
                  }
                }
                defer {
                  batchQueue.continuation.finish()
                }
                do {
                  for try await part in contents.bodyParts {
                    guard case .message(let msg) = part else { continue }
                    receivedAnyResponse.value.store(true, ordering: .releasing)
                    watchdog.markResponseReceived()

                    let batchEOD = self.state.withLock { state -> Bool in
                      if msg.hasSubscriptionProperties {
                        state.sessionExactlyOnce =
                          msg.subscriptionProperties.exactlyOnceDeliveryEnabled
                      }
                      if !msg.receivedMessages.isEmpty {
                        for proto in msg.receivedMessages {
                          state.pendingRawAckIDs[proto.ackID, default: 0] += 1
                        }
                      }
                      return msg.hasSubscriptionProperties
                        ? msg.subscriptionProperties.exactlyOnceDeliveryEnabled
                        : state.sessionExactlyOnce
                    }

                    if !msg.receivedMessages.isEmpty {
                      batchQueue.continuation.yield(
                        PendingBatch(
                          protos: msg.receivedMessages,
                          isExactlyOnce: batchEOD,
                          gate: gate
                        )
                      )
                    }
                  }
                  batchQueue.continuation.finish()
                  await deliveryTask.value
                } catch {
                  batchQueue.continuation.finish()
                  deliveryTask.cancel()
                  _ = await deliveryTask.result
                  throw error
                }
              }
            }
          )
        }

        group.addTask {
          for await _ in pongTimedOut.stream {
            outbound.continuation.finish()
            throw PongTimeoutError()
          }
        }

        _ = try await group.next()
        outbound.continuation.finish()
        pongTimedOut.continuation.finish()
        group.cancelAll()
      }
    } catch {
      if timedOutBox.value.load(ordering: .acquiring) {
        throw PongTimeoutError()
      }
      throw error
    }

    if timedOutBox.value.load(ordering: .acquiring) {
      throw PongTimeoutError()
    }
  }

  private func admitAndDeliverBatch(
    protos: [Google_Pubsub_V1_ReceivedMessage],
    isExactlyOnce: Bool,
    gate: SubscriberFlowGate
  ) async {
    guard !protos.isEmpty else { return }

    struct PreparedMessage {
      let ackID: String
      let message: Message
      let byteSize: Int
    }
    let prepared: [PreparedMessage] = protos.map { proto in
      let message = Self.convertProtoMessage(proto)
      let wireBytes = max(1, message.estimatedWireByteSize())
      return PreparedMessage(ackID: proto.ackID, message: message, byteSize: wireBytes)
    }

    if isExactlyOnce {
      var incoming: [LeaseManager.IncomingLeaseItem] = []
      var entries:
        [(
          entry: PreparedMessage,
          acquiredBox: AtomicFlag,
          tracker: LeaseTracker
        )] = []
      incoming.reserveCapacity(prepared.count)
      entries.reserveCapacity(prepared.count)
      for entry in prepared {
        let acquiredBox = AtomicFlag()
        let handler = self.leaseManager.makeAckHandler(ackID: entry.ackID, isExactlyOnce: true)
        let tracker = LeaseTracker(handler: handler) { [gate, byteSize = entry.byteSize] in
          if acquiredBox.value.load(ordering: .acquiring) {
            gate.release(bytes: byteSize)
          }
        }
        entries.append((entry: entry, acquiredBox: acquiredBox, tracker: tracker))
        incoming.append(.init(ackID: entry.ackID, leaseTracker: tracker))
      }
      let survived = await self.leaseManager.registerBatch(incoming, isExactlyOnce: true)
      let survivingSet = Set(survived.map(\.ackID))
      self.removePendingRawAckIDs(prepared.filter { !survivingSet.contains($0.ackID) }.map(\.ackID))

      func abortRemaining(from startIndex: Int) {
        let isStopping = self.state.withLock { $0.stopInitiated }
        var remainingAckIDs: [String] = []
        var uniqueRemaining: [String] = []
        var seen: Set<String> = []
        for idx in startIndex..<entries.count {
          let item = entries[idx]
          if survivingSet.contains(item.entry.ackID) {
            item.tracker.markExpired()
            remainingAckIDs.append(item.entry.ackID)
            if seen.insert(item.entry.ackID).inserted {
              uniqueRemaining.append(item.entry.ackID)
            }
          }
        }
        self.removePendingRawAckIDs(remainingAckIDs)
        if !isStopping {
          for ackID in uniqueRemaining {
            self.leaseManager.nack(ackID: ackID, isExactlyOnce: true, options: .init())
          }
        }
      }

      for idx in entries.indices {
        let item = entries[idx]
        guard survivingSet.contains(item.entry.ackID) else { continue }
        if Task.isCancelled || self.state.withLock({ $0.stopInitiated }) {
          abortRemaining(from: idx)
          return
        }
        do {
          try await gate.acquire(bytes: item.entry.byteSize)
        } catch {
          abortRemaining(from: idx)
          return
        }
        item.acquiredBox.value.store(true, ordering: .releasing)
        if Task.isCancelled || self.state.withLock({ $0.stopInitiated }) {
          abortRemaining(from: idx)
          return
        }
        let received = ReceivedMessage(
          message: item.entry.message,
          isExactlyOnce: true,
          leaseTracker: item.tracker
        )
        if !self.deliverOrEnqueue(ackID: item.entry.ackID, message: received) {
          abortRemaining(from: idx)
          return
        }
      }
      return
    }

    // Standard at-least-once: batch-acquire unblocked flow-control permits and register synchronously.
    let fastCount = gate.tryAcquirePrefix(count: prepared.count) { prepared[$0].byteSize }
    if fastCount > 0 {
      if Task.isCancelled || self.state.withLock({ $0.stopInitiated }) {
        for idx in 0..<fastCount {
          gate.release(bytes: prepared[idx].byteSize)
        }
        return
      }
      var leaseItems: [LeaseManager.IncomingLeaseItem] = []
      var batchItems: [(ackID: String, message: ReceivedMessage, tracker: LeaseTracker)] = []
      leaseItems.reserveCapacity(fastCount)
      batchItems.reserveCapacity(fastCount)
      for idx in 0..<fastCount {
        let entry = prepared[idx]
        let tracker = LeaseTracker(
          leaseManager: self.leaseManager,
          ackID: entry.ackID,
          isExactlyOnce: false,
          releaseTarget: .flowGate(gate, bytes: entry.byteSize)
        )
        leaseItems.append(.init(ackID: entry.ackID, leaseTracker: tracker))
        let received = ReceivedMessage(
          message: entry.message,
          isExactlyOnce: false,
          leaseTracker: tracker
        )
        batchItems.append((ackID: entry.ackID, message: received, tracker: tracker))
      }
      let survived = self.leaseManager.registerNonEODBatchSync(leaseItems)
      guard !survived.isEmpty else {
        self.removePendingRawAckIDs(batchItems.map(\.ackID))
        return
      }
      if !self.deliverOrEnqueueBatch(batchItems) {
        let isStopping = self.state.withLock { $0.stopInitiated }
        let failedIDs = batchItems.map(\.ackID)
        for item in batchItems {
          item.tracker.markExpired()
        }
        self.removePendingRawAckIDs(failedIDs)
        if !isStopping {
          for ackID in Set(failedIDs) {
            self.leaseManager.nack(ackID: ackID, isExactlyOnce: false, options: .init())
          }
        }
        return
      }
    }

    for idx in fastCount..<prepared.count {
      let entry = prepared[idx]
      if Task.isCancelled || self.state.withLock({ $0.stopInitiated }) {
        return
      }
      do {
        try await gate.acquire(bytes: entry.byteSize)
      } catch {
        return
      }
      if self.state.withLock({ $0.stopInitiated }) {
        gate.release(bytes: entry.byteSize)
        return
      }
      let tracker = LeaseTracker(
        leaseManager: self.leaseManager,
        ackID: entry.ackID,
        isExactlyOnce: false,
        releaseTarget: .flowGate(gate, bytes: entry.byteSize)
      )
      let survived = self.leaseManager.registerNonEODBatchSync(
        [.init(ackID: entry.ackID, leaseTracker: tracker)]
      )
      guard !survived.isEmpty else {
        self.removePendingRawAckIDs([entry.ackID])
        return
      }
      let received = ReceivedMessage(
        message: entry.message,
        isExactlyOnce: false,
        leaseTracker: tracker
      )
      if !self.deliverOrEnqueue(ackID: entry.ackID, message: received) {
        let isStopping = self.state.withLock { $0.stopInitiated }
        tracker.markExpired()
        self.removePendingRawAckIDs([entry.ackID])
        if !isStopping {
          self.leaseManager.nack(ackID: entry.ackID, isExactlyOnce: false, options: .init())
        }
        return
      }
    }
  }

  private static func decrementPendingRawAckIDLocked(
    _ ackID: String,
    in state: inout State
  ) {
    guard let count = state.pendingRawAckIDs[ackID] else { return }
    if count <= 1 {
      state.pendingRawAckIDs.removeValue(forKey: ackID)
    } else {
      state.pendingRawAckIDs[ackID] = count - 1
    }
  }

  private func deliverOrEnqueue(ackID: String, message: ReceivedMessage) -> Bool {
    enum DeliverAction {
      case rejected
      case queued
      case resume(CheckedContinuation<ReceivedMessage?, any Error>)
    }
    let action: DeliverAction = self.state.withLock { state in
      if state.stopInitiated || state.terminalError != nil {
        return .rejected
      }
      Self.decrementPendingRawAckIDLocked(ackID, in: &state)
      if !state.nextWaiters.isEmpty {
        return .resume(state.nextWaiters.removeFirst().continuation)
      }
      state.readyQueue.append((ackID: ackID, message: message))
      return .queued
    }
    switch action {
    case .rejected:
      return false
    case .queued:
      return true
    case .resume(let cont):
      cont.resume(returning: message)
      return true
    }
  }

  private func deliverOrEnqueueBatch(
    _ items: [(ackID: String, message: ReceivedMessage, tracker: LeaseTracker)]
  ) -> Bool {
    let resumeList:
      [(continuation: CheckedContinuation<ReceivedMessage?, any Error>, message: ReceivedMessage)]? =
        self.state.withLock { state in
          if state.stopInitiated || state.terminalError != nil {
            return nil
          }
          var toResume: [(CheckedContinuation<ReceivedMessage?, any Error>, ReceivedMessage)] = []
          for item in items {
            Self.decrementPendingRawAckIDLocked(item.ackID, in: &state)
            if !state.nextWaiters.isEmpty {
              toResume.append((state.nextWaiters.removeFirst().continuation, item.message))
            } else {
              state.readyQueue.append((ackID: item.ackID, message: item.message))
            }
          }
          return toResume
        }
    guard let resumeList else {
      return false
    }
    for entry in resumeList {
      entry.continuation.resume(returning: entry.message)
    }
    return true
  }

  private func removePendingRawAckIDs(_ ackIDs: [String]) {
    guard !ackIDs.isEmpty else { return }
    self.state.withLock { state in
      for ackID in ackIDs {
        state.pendingRawAckIDs.removeValue(forKey: ackID)
      }
    }
  }

  static func convertProtoMessage(_ received: Google_Pubsub_V1_ReceivedMessage) -> Message {
    let pb = received.message
    var msg = Message(
      data: pb.data,
      attributes: pb.attributes,
      orderingKey: pb.orderingKey
    )
    msg.messageID = pb.messageID
    if pb.hasPublishTime {
      msg.publishTime =
        (try? GoogleWKT.WKTTimestamp(proto: pb.publishTime))
        ?? GoogleWKT.WKTTimestamp(
          clampingSeconds: pb.publishTime.seconds,
          nanos: pb.publishTime.nanos
        )
    }
    msg.deliveryAttempt = received.deliveryAttempt > 0 ? Int(received.deliveryAttempt) : nil
    return msg
  }

  private static func clampedDeadlineSeconds(_ duration: Duration) -> Int32 {
    let comps = duration.components
    var secs = comps.seconds
    if comps.attoseconds > 0 { secs += 1 }
    if secs < 10 { return 10 }
    if secs > 600 { return 600 }
    return Int32(secs)
  }
}
