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

/// Implements a probabilistic throttler based on observed failure rates.
///
/// This is an implementation of the [Adaptive Throttling] strategy described in [Site Reliability
/// Engineering] book. The basic idea is to *stochastically* reject some of the retry attempts, with
/// a rejection probability that increases as the number of failures increases, and decreases with
/// the number of successful requests.
///
/// The rejection rate probability is defined by:
///
/// ```
/// threshold = (requests - factor * accepts) / (requests + 1)
/// rejection_probability = max(0, threshold)
/// ```
///
/// Where `requests` is the number of requests completed, and `accepts` is the number of requests
/// accepted by the service, including requests that fail due to parameter validation, authorization
/// checks, or any non-transient failures.
///
/// Note that `accepts <= requests` but the `threshold` value might be negative as `factor` can be
/// higher than `1.0`. In fact, the SRE book recommends using `2.0` as the initial factor.
///
/// Setting `factor` to lower values makes the algorithm reject retry attempts with higher
/// probability. For example, setting it to zero would reject some retry attempts even if all
/// requests have succeeded. Setting `factor` to higher values allows more retry attempts.
///
/// [Site Reliability Engineering]: https://sre.google/sre-book/table-of-contents/
/// [Adaptive Throttling]: https://sre.google/sre-book/handling-overload/
public final class AdaptiveThrottler: RetryThrottler, Sendable {
  private struct State {
    var acceptCount: Double = 0.0
    var requestCount: Double = 0.0
  }

  private let factor: Double
  private let state = Mutex(State())

  /// Creates a new adaptive throttler with a factor of 2.
  public init() {
    self.factor = 2.0
  }

  /// Creates a new adaptive throttler with the given `factor`.
  ///
  /// - Parameter factor: A factor to adjust the relative weight of transient
  ///   failures vs. accepted requests.
  /// - Throws: ``RetryThrottlerError/scalingOutOfRange(_:)`` if `factor` is negative.
  public init(factor: Double) throws {
    if factor < 0.0 {
      throw RetryThrottlerError.scalingOutOfRange(factor)
    }
    self.factor = factor
  }

  /// Creates a new adaptive throttler clamping `factor` to a valid range.
  ///
  /// - Parameter factor: A factor to adjust the relative weight of transient
  ///   failures vs. accepted requests. Clamped to zero if the value is negative.
  public init(clamping factor: Double) {
    self.factor = max(0.0, factor)
  }

  public func throttleRetryAttempt() -> Bool {
    throttleRetryAttemptImpl(gen: { () in Double.random(in: 0.0...1.0) })
  }

  public func onRetryFailure(flow: RetryResult) {
    state.withLock { state in
      state.requestCount += 1.0
      switch flow {
      case .retry, .exhausted:
        break
      case .permanent:
        state.acceptCount += 1.0
      }
    }
  }

  public func onSuccess() {
    state.withLock { state in
      state.requestCount += 1.0
      state.acceptCount += 1.0
    }
  }

  // A testable version of `throttleRetryAttempt()` with dependency injection for the pseudo-random
  // number generator.
  func throttleRetryAttemptImpl(gen: () -> Double) -> Bool {
    return state.withLock { state in
      let rejectProbability =
        (state.requestCount - factor * state.acceptCount) / (state.requestCount + 1.0)
      let p = max(0.0, rejectProbability)
      if p <= 0.0 { return false }
      if p >= 1.0 { return true }
      return gen() <= p
    }
  }
}
