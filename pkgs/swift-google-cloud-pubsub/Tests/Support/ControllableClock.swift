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

import Foundation
import GoogleCloudPubSub
import Synchronization

package final class ControllableClock: PubSubClock, Sendable {
  private final class WaiterBox: Sendable {
    enum Outcome: Sendable {
      case pending
      case succeeded
      case cancelled
    }

    private struct State: Sendable {
      var outcome: Outcome = .pending
      var continuation: CheckedContinuation<Void, any Error>?
    }

    let id: UInt64
    let deadline: ContinuousClock.Instant
    private let state = Mutex(State())

    init(id: UInt64, deadline: ContinuousClock.Instant) {
      self.id = id
      self.deadline = deadline
    }

    func attachOrResolve(_ continuation: CheckedContinuation<Void, any Error>) {
      let immediate = self.state.withLock { state -> Outcome? in
        switch state.outcome {
        case .pending:
          state.continuation = continuation
          return nil
        case .succeeded, .cancelled:
          return state.outcome
        }
      }
      switch immediate {
      case .succeeded:
        continuation.resume()
      case .cancelled:
        continuation.resume(throwing: CancellationError())
      case .pending, nil:
        break
      }
    }

    func markSucceededAndTakeContinuation() -> CheckedContinuation<Void, any Error>? {
      self.state.withLock { state in
        guard state.outcome == .pending else { return nil }
        state.outcome = .succeeded
        let cont = state.continuation
        state.continuation = nil
        return cont
      }
    }

    func markCancelledAndTakeContinuation() -> CheckedContinuation<Void, any Error>? {
      self.state.withLock { state in
        guard state.outcome == .pending else { return nil }
        state.outcome = .cancelled
        let cont = state.continuation
        state.continuation = nil
        return cont
      }
    }
  }

  private struct State: Sendable {
    var currentNow: ContinuousClock.Instant
    var nextID: UInt64 = 1
    var waiters: [WaiterBox] = []
    var sleepNotifyWaiters: [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)] =
      []
    var totalSleepsStarted: Int = 0
  }

  private let state: Mutex<State>

  package init(start: ContinuousClock.Instant = ContinuousClock.now) {
    self.state = Mutex(State(currentNow: start))
  }

  package var now: ContinuousClock.Instant {
    self.state.withLock { $0.currentNow }
  }

  package var pendingWaiterCount: Int {
    self.state.withLock { $0.waiters.count }
  }

  package var sleepsStarted: Int {
    self.state.withLock { $0.totalSleepsStarted }
  }

  package func sleep(for duration: Duration) async throws {
    if duration <= .zero {
      try Task.checkCancellation()
      return
    }
    if Task.isCancelled {
      throw CancellationError()
    }

    let id = self.state.withLock { state -> UInt64 in
      let assigned = state.nextID
      state.nextID += 1
      return assigned
    }
    let (waiter, toWake) = self.state.withLock {
      state -> (WaiterBox, [CheckedContinuation<Void, Never>]) in
      let box = WaiterBox(id: id, deadline: state.currentNow + duration)
      state.waiters.append(box)
      state.totalSleepsStarted += 1
      let activeCount = state.waiters.count
      var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
      var ready: [CheckedContinuation<Void, Never>] = []
      for entry in state.sleepNotifyWaiters {
        if activeCount >= entry.targetCount {
          ready.append(entry.continuation)
        } else {
          remaining.append(entry)
        }
      }
      state.sleepNotifyWaiters = remaining
      return (box, ready)
    }
    for cont in toWake {
      cont.resume()
    }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled && self.removeWaiter(id: waiter.id) {
          _ = waiter.markCancelledAndTakeContinuation()
          continuation.resume(throwing: CancellationError())
          return
        }
        waiter.attachOrResolve(continuation)
        let shouldFireImmediately = self.state.withLock { state -> Bool in
          guard waiter.deadline <= state.currentNow else {
            return false
          }
          let before = state.waiters.count
          state.waiters.removeAll { $0.id == waiter.id }
          return state.waiters.count < before
        }
        if shouldFireImmediately {
          waiter.markSucceededAndTakeContinuation()?.resume()
        } else if Task.isCancelled && self.removeWaiter(id: waiter.id) {
          waiter.markCancelledAndTakeContinuation()?.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      if self.removeWaiter(id: id),
        let cont = waiter.markCancelledAndTakeContinuation()
      {
        cont.resume(throwing: CancellationError())
      }
    }
  }

  private func removeWaiter(id: UInt64) -> Bool {
    self.state.withLock { state in
      let before = state.waiters.count
      state.waiters.removeAll { $0.id == id }
      return state.waiters.count < before
    }
  }

  package func advance(by duration: Duration) {
    let toWake = self.state.withLock { state -> [WaiterBox] in
      state.currentNow += duration
      let ready = state.waiters.filter { $0.deadline <= state.currentNow }
        .sorted { $0.deadline < $1.deadline }
      state.waiters.removeAll { $0.deadline <= state.currentNow }
      return ready
    }
    for waiter in toWake {
      waiter.markSucceededAndTakeContinuation()?.resume()
    }
  }

  package func waitUntilWaiters(atLeast count: Int) async {
    await withCheckedContinuation { continuation in
      let alreadyMet = self.state.withLock { state -> Bool in
        if state.waiters.count >= count {
          return true
        }
        state.sleepNotifyWaiters.append((count, continuation))
        return false
      }
      if alreadyMet {
        continuation.resume()
      }
    }
  }
}
