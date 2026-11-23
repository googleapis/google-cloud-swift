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
import Synchronization

package struct PublishPermit: Sendable {
  package let messages: Int
  package let bytes: Int
}

package final class PublisherFlowController: Sendable {
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
    var pendingMessages: Int = 0
    var pendingBytes: Int = 0
    var nextWaiterID: UInt64 = 1
    var waiters: Deque<Waiter> = []
  }

  private let options: PublisherFlowControlOptions
  private let state = Mutex(State())

  package init(_ options: PublisherFlowControlOptions) {
    self.options = options
  }

  package var snapshot: (pendingMessages: Int, pendingBytes: Int) {
    self.state.withLock { ($0.pendingMessages, $0.pendingBytes) }
  }

  /// Synchronously acquires a permit when flow-control allows immediate admission,
  /// returning `nil` only when `.block` must suspend on a full watermark.
  package func tryAcquireImmediate(bytes: Int) throws -> PublishPermit? {
    switch self.options.limitExceededBehavior {
    case .ignore:
      return PublishPermit(messages: 0, bytes: 0)

    case .signalError:
      return try self.state.withLock { state in
        if let limit = self.options.maxPendingMessages, state.pendingMessages + 1 > limit {
          throw PubSubError.flowControlLimitExceeded(
            .messageCount(pending: state.pendingMessages + 1, limit: limit)
          )
        }
        if let limitBytes = self.options.maxPendingBytes, state.pendingBytes + bytes > limitBytes {
          throw PubSubError.flowControlLimitExceeded(
            .byteCount(pendingBytes: state.pendingBytes + bytes, limitBytes: limitBytes)
          )
        }
        state.pendingMessages += 1
        state.pendingBytes += bytes
        return PublishPermit(messages: 1, bytes: bytes)
      }

    case .block:
      try Task.checkCancellation()
      return self.state.withLock { state in
        if state.waiters.isEmpty
          && Self.canAcquire(bytes: bytes, state: state, options: self.options)
        {
          state.pendingMessages += 1
          state.pendingBytes += bytes
          return PublishPermit(messages: 1, bytes: bytes)
        }
        return nil
      }

    @unknown default:
      return PublishPermit(messages: 0, bytes: 0)
    }
  }

  package func acquire(bytes: Int) async throws -> PublishPermit {
    switch self.options.limitExceededBehavior {
    case .ignore:
      return PublishPermit(messages: 0, bytes: 0)

    case .signalError:
      return try self.state.withLock { state in
        if let limit = self.options.maxPendingMessages, state.pendingMessages + 1 > limit {
          throw PubSubError.flowControlLimitExceeded(
            .messageCount(pending: state.pendingMessages + 1, limit: limit)
          )
        }
        if let limitBytes = self.options.maxPendingBytes, state.pendingBytes + bytes > limitBytes {
          throw PubSubError.flowControlLimitExceeded(
            .byteCount(pendingBytes: state.pendingBytes + bytes, limitBytes: limitBytes)
          )
        }
        state.pendingMessages += 1
        state.pendingBytes += bytes
        return PublishPermit(messages: 1, bytes: bytes)
      }

    case .block:
      try Task.checkCancellation()
      enum ImmediateResult {
        case acquired(PublishPermit)
        case wait(Waiter)
      }

      let outcome = self.state.withLock { state -> ImmediateResult in
        if state.waiters.isEmpty
          && Self.canAcquire(bytes: bytes, state: state, options: self.options)
        {
          state.pendingMessages += 1
          state.pendingBytes += bytes
          return .acquired(PublishPermit(messages: 1, bytes: bytes))
        }
        let id = state.nextWaiterID
        state.nextWaiterID += 1
        let waiter = Waiter(id: id, bytes: bytes)
        state.waiters.append(waiter)
        return .wait(waiter)
      }

      switch outcome {
      case .acquired(let permit):
        return permit

      case .wait(let waiter):
        try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            if Task.isCancelled && self.removePendingWaiter(id: waiter.id) {
              _ = waiter.markCancelledAndTakeContinuation()
              continuation.resume(throwing: CancellationError())
              self.wakeReadyWaiters()
            } else {
              waiter.attachOrResolve(continuation)
            }
          }
        } onCancel: {
          if self.removePendingWaiter(id: waiter.id),
            let continuationToCancel = waiter.markCancelledAndTakeContinuation()
          {
            continuationToCancel.resume(throwing: CancellationError())
          }
          self.wakeReadyWaiters()
        }
        return PublishPermit(messages: 1, bytes: bytes)
      }

    @unknown default:
      return PublishPermit(messages: 0, bytes: 0)
    }
  }

  private func removePendingWaiter(id: UInt64) -> Bool {
    self.state.withLock { state in
      let before = state.waiters.count
      state.waiters.removeAll { $0.id == id }
      return state.waiters.count < before
    }
  }

  package func release(_ permit: PublishPermit) {
    guard permit.messages > 0 || permit.bytes > 0 else {
      return
    }
    let ready = self.state.withLock { state -> [CheckedContinuation<Void, any Error>] in
      state.pendingMessages = max(0, state.pendingMessages - permit.messages)
      state.pendingBytes = max(0, state.pendingBytes - permit.bytes)
      return self.popReadyContinuationsLocked(state: &state)
    }
    for continuation in ready {
      continuation.resume()
    }
  }

  private func wakeReadyWaiters() {
    let ready = self.state.withLock { state in
      self.popReadyContinuationsLocked(state: &state)
    }
    for continuation in ready {
      continuation.resume()
    }
  }

  private func popReadyContinuationsLocked(
    state: inout State
  ) -> [CheckedContinuation<Void, any Error>] {
    var ready: [CheckedContinuation<Void, any Error>] = []
    while let head = state.waiters.first {
      guard Self.canAcquire(bytes: head.bytes, state: state, options: self.options) else {
        break
      }
      state.waiters.removeFirst()
      state.pendingMessages += 1
      state.pendingBytes += head.bytes
      if let cont = head.markGrantedAndTakeContinuation() {
        ready.append(cont)
      }
    }
    return ready
  }

  private static func canAcquire(
    bytes: Int,
    state: State,
    options: PublisherFlowControlOptions
  ) -> Bool {
    if state.pendingMessages == 0 && state.pendingBytes == 0 {
      if let limit = options.maxPendingMessages, limit < 1 {
        return false
      }
      // Idle singleton exception (`PFC-02`): admit one valid message when completely idle.
      return bytes <= Message.maxSingleMessageBytes
    }
    if let limit = options.maxPendingMessages, state.pendingMessages + 1 > limit {
      return false
    }
    if let limitBytes = options.maxPendingBytes, state.pendingBytes + bytes > limitBytes {
      return false
    }
    return true
  }
}

package final class HedgingTokenBucket: Sendable {
  private let maxMilliTokens: Int
  private let refillMilliTokens: Int
  private let milliTokens = Mutex(0)

  package init(_ options: HedgingOptions) {
    self.maxMilliTokens = max(1, options.maxTokens) * 1_000
    self.refillMilliTokens = max(1, Int((options.refillRatio * 1_000.0).rounded()))
  }

  package var currentMilliTokens: Int {
    self.milliTokens.withLock { $0 }
  }

  package func recordSuccess() {
    self.milliTokens.withLock { tokens in
      tokens = min(self.maxMilliTokens, tokens + self.refillMilliTokens)
    }
  }

  package func tryConsumeHedgeToken() -> Bool {
    self.milliTokens.withLock { tokens in
      guard tokens >= 1_000 else {
        return false
      }
      tokens -= 1_000
      return true
    }
  }
}
