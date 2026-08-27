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
import Synchronization

/// This implementation was inspired by the `ManualClock` in Apple's `swift-async-algorithms` project.
///
/// A mock clock that allows manual advancement of time for deterministic testing.
///
/// ### Sample Usage
///
/// ```swift
/// let clock = TestClock()
///
/// let task = Task {
///   try await clock.sleep(for: .seconds(1))
///   print("Woke up!")
/// }
///
/// // 1. Wait for the sleeper to register on the clock deterministically!
/// await clock.sleeperWaiting()
///
/// // 2. Advance simulated time to wake up the sleeper!
/// clock.advance(by: .seconds(1))
///
/// await task.value // Prints "Woke up!"
/// ```
final class TestClock: Clock, Sendable {
  /// Represents a specific point in time on the `TestClock`.
  struct Instant: InstantProtocol, Equatable {
    typealias Duration = Swift.Duration
    let offset: Swift.Duration

    func advanced(by duration: Swift.Duration) -> Instant {
      Instant(offset: offset + duration)
    }

    func duration(to other: Instant) -> Swift.Duration {
      other.offset - offset
    }

    static func < (lhs: Instant, rhs: Instant) -> Bool {
      lhs.offset < rhs.offset
    }

    static func == (lhs: Instant, rhs: Instant) -> Bool {
      lhs.offset == rhs.offset
    }
  }

  typealias Duration = Swift.Duration

  /// Synchronous state of the clock, protected by Mutex.
  struct State {
    var now: Instant = Instant(offset: .zero)
    // Using a Dictionary is optimized for insert/cancel and keeps mock code simple.
    // Linear scans during advance() are negligible since unit tests only have a handful of concurrent sleepers.
    var sleepers: [Int: (deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] =
      [:]
    var nextGeneration = 0

    var sleepContinuations: [CheckedContinuation<Void, Never>] = []

    mutating func getNextGeneration() -> Int {
      let g = nextGeneration
      nextGeneration += 1
      return g
    }

    mutating func advance(by duration: Duration) -> [CheckedContinuation<Void, any Error>] {
      now = now.advanced(by: duration)
      let currentNow = now

      let readyKeys = sleepers.filter { $0.value.deadline <= currentNow }.map { $0.key }
      var ready: [CheckedContinuation<Void, any Error>] = []
      for key in readyKeys {
        if let sleeper = sleepers.removeValue(forKey: key) {
          ready.append(sleeper.continuation)
        }
      }
      return ready
    }

    var hasSleepers: Bool {
      !sleepers.isEmpty
    }

    mutating func registerSleepContinuation(_ continuation: CheckedContinuation<Void, Never>)
      -> CheckedContinuation<Void, Never>?
    {
      if !sleepers.isEmpty {
        return continuation
      }
      sleepContinuations.append(continuation)
      return nil
    }

    mutating func registerSleeper(
      gen: Int,
      deadline: Instant,
      continuation: CheckedContinuation<Void, any Error>,
      shouldResumeImmediately: inout Bool,
      shouldResumeWithCancellation: inout Bool
    ) -> [CheckedContinuation<Void, Never>] {
      if Task.isCancelled {
        shouldResumeWithCancellation = true
        return []
      }
      if deadline <= now {
        shouldResumeImmediately = true
        return []
      }
      sleepers[gen] = (deadline, continuation)

      let toResume = sleepContinuations
      sleepContinuations.removeAll()
      return toResume
    }

    mutating func removeSleeper(forKey key: Int) -> (
      deadline: Instant, continuation: CheckedContinuation<Void, any Error>
    )? {
      sleepers.removeValue(forKey: key)
    }
  }

  private let state: Mutex<State>

  init() {
    self.state = Mutex(State())
  }

  /// Suspends the test thread until a background task goes to sleep on this clock.
  /// If a task is already sleeping, returns instantly.
  public func sleeperWaiting() async {
    let shouldResumeImmediately = state.withLock { $0.hasSleepers }
    if shouldResumeImmediately {
      return
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let readySleepContinuation = state.withLock { state in
        state.registerSleepContinuation(continuation)
      }
      if let ready = readySleepContinuation {
        ready.resume()
      }
    }
  }

  /// The current simulated time.
  var now: Instant {
    state.withLock { $0.now }
  }

  /// Returns true if there are tasks currently suspended waiting for time to advance.
  var hasSleepers: Bool {
    state.withLock { $0.hasSleepers }
  }

  /// The minimum resolution of the clock. Always returns .zero as it has infinite resolution.
  var minimumResolution: Duration { .zero }

  /// Suspends the calling task until mock time reaches the deadline.
  /// Automatically resumes any test threads currently waiting for a sleeper.
  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    let gen = state.withLock { $0.getNextGeneration() }

    var shouldResumeImmediately = false
    var shouldResumeWithCancellation = false

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let sleepContinuationsToResume = state.withLock { state in
          state.registerSleeper(
            gen: gen,
            deadline: deadline,
            continuation: continuation,
            shouldResumeImmediately: &shouldResumeImmediately,
            shouldResumeWithCancellation: &shouldResumeWithCancellation
          )
        }

        // Resume sleep() callers outside the lock to prevent deadlocks
        for sleepContinuation in sleepContinuationsToResume {
          sleepContinuation.resume()
        }

        // Resume outside the lock to prevent deadlocks
        if shouldResumeWithCancellation {
          continuation.resume(throwing: CancellationError())
        } else if shouldResumeImmediately {
          continuation.resume()
        }
      }
    } onCancel: {
      let sleeper = state.withLock { $0.removeSleeper(forKey: gen) }
      if let s = sleeper {
        s.continuation.resume(throwing: CancellationError())
      }
    }
  }

  /// Advances mock time by the given duration and resumes all tasks whose deadlines have passed.
  func advance(by duration: Duration) {
    let readyContinuations = state.withLock { $0.advance(by: duration) }

    for continuation in readyContinuations {
      continuation.resume()
    }
  }
}
