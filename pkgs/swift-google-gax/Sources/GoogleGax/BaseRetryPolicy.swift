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
import GoogleRpc

/// A combination of retry policies that works for most services.
///
/// Use ``defaultPolicy`` for the standard bounded configuration (60-second time limit and
/// 10-attempt limit), or ``unbounded()`` decorated with ``RetryPolicy/withTimeLimit(_:)``
/// and/or ``RetryPolicy/withAttemptLimit(_:)`` to configure custom limits.
///
/// This policy only retries [idempotent] operations, and then only if the error is an I/O error, or a safe error code.
///
/// [AIP-194]: https://google.aip.dev/194
/// [idempotent]: https://en.wikipedia.org/wiki/Idempotence
public struct BaseRetryPolicy: RetryPolicy, Sendable, Equatable {
  let inner: StrictIdempotency<ContinueOnIO<Aip194>>

  public init() {
    self.inner = Aip194().retryOnIO().strictIdempotency()
  }

  /// Creates an unconstrained base retry policy without attempt or time limits.
  ///
  /// Decorate this policy with ``RetryPolicy/withTimeLimit(_:)`` and/or
  /// ``RetryPolicy/withAttemptLimit(_:)`` to bound the retry loop:
  /// ```swift
  /// let policy = BaseRetryPolicy.unbounded()
  ///   .withTimeLimit(.seconds(30))
  ///   .withAttemptLimit(5)
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators,
  ///   this policy retries transient errors indefinitely.
  public static func unbounded() -> BaseRetryPolicy {
    BaseRetryPolicy()
  }

  /// The default retry policy, with a 60-second time limit and 10-attempt limit.
  public static var defaultPolicy: some RetryPolicy {
    BaseRetryPolicy.unbounded().withTimeLimit(.seconds(60)).withAttemptLimit(10)
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    self.inner.onError(state: state, error: error)
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    self.inner.onThrottle(state: state, error: error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    self.inner.remainingTime(state: state)
  }
}
