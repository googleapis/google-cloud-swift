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

/// A retry policy decorator that limits the total time in the retry loop.
///
/// If the time elapsed in the retry loop, including any backoff, is larger than the prescribed
/// duration then the policy returns ``RetryResult/exhausted(_:)``. Otherwise, the policy returns
/// the result from the inner policy.
///
/// The `remainingTime()` method returns the remaining time. This is always zero after the
/// policy's deadline is reached.
final public class LimitedElapsedTime<P: RetryPolicy>: RetryPolicy {
  let inner: P
  let maximumDuration: Duration

  public init(inner: P, maximumDuration: Duration) {
    self.inner = inner
    self.maximumDuration = maximumDuration
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    switch inner.onError(state: state, error: error) {
    case .permanent(let e):
      return .permanent(e)
    case .exhausted(let e):
      return .exhausted(e)
    case .retry(let e):
      if ContinuousClock.now >= state.start + maximumDuration {
        return .exhausted(e)
      }
      return .retry(e)
    }
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    switch inner.onThrottle(state: state, error: error) {
    case .exhausted(let e):
      return .exhausted(e)
    case .retry(let e):
      if ContinuousClock.now >= state.start + maximumDuration {
        return .exhausted(
          .exhausted(LimitedElapsedTimeError(maximumDuration: maximumDuration, source: e)))
      }
      return .retry(e)
    }
  }

  public func remainingTime(state: RetryState) -> Duration? {
    let deadline = state.start + maximumDuration
    let now = ContinuousClock.now
    let remaining = now < deadline ? (deadline - now) : .zero
    if let innerRemaining = inner.remainingTime(state: state) {
      return min(remaining, innerRemaining)
    }
    return remaining
  }
}

extension RetryPolicy {
  /// Decorate a `RetryPolicy` to limit the total elapsed time in the retry loop.
  ///
  /// - Parameter maximumDuration: The maximum duration allowed by the policy.
  /// - Returns: A decorated retry policy.
  public func withTimeLimit(_ maximumDuration: Duration) -> LimitedElapsedTime<Self> {
    LimitedElapsedTime(inner: self, maximumDuration: maximumDuration)
  }
}
