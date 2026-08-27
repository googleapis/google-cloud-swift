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

/// A retry policy decorator that is very conservative with respect to [idempotency].
///
/// This policy returns [.permanent](``ResultResult.permanent(_:)``) if the request is not
/// idempotent. Otherwise it returns the result of calling the decorated policy.
///
/// [idempotency]: https://en.wikipedia.org/wiki/Idempotence
public struct StrictIdempotency<P: RetryPolicy>: RetryPolicy {
  let inner: P

  public init(inner: P) {
    self.inner = inner
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    if !state.idempotent {
      return .permanent(error)
    }
    return inner.onError(state: state, error: error)
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    if !state.idempotent {
      return .exhausted(error)
    }
    return inner.onThrottle(state: state, error: error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension RetryPolicy {
  /// Decorate a `RetryPolicy` to stop if the request is not-idempotent.
  ///
  /// This policy decorates an inner policy and stops with
  /// [.permanent](``ResultResult.permanent(_:)``) if the request is not idempotent.
  public func strictIdempotency() -> StrictIdempotency<Self> {
    StrictIdempotency(inner: self)
  }
}
