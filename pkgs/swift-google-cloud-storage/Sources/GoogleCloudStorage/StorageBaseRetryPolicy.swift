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
public import GoogleGax
import GoogleRpc

/// A base retry policy for Google Cloud Storage that retries transient errors on idempotent requests.
///
/// This policy retries idempotent operations that fail with I/O errors, transient HTTP status codes
/// (408, 429, and 5xx), or transient gRPC status codes (`unavailable`, `resourceExhausted`,
/// `deadlineExceeded`, and `internal`).
///
/// Use ``defaultPolicy`` for the standard bounded configuration (60-second time limit and
/// 10-attempt limit), or ``unbounded()`` decorated with `withTimeLimit(_:)`
/// and/or `withAttemptLimit(_:)` to configure custom limits.
public struct StorageBaseRetryPolicy: Sendable, Equatable {
  let inner: StrictIdempotency<ContinueOnIO<StorageRetryErrors>>

  public init() {
    self.inner = StorageRetryErrors().retryOnIO().strictIdempotency()
  }

  /// Creates an unconstrained Cloud Storage base retry policy without attempt or time limits.
  ///
  /// Decorate this policy with `withTimeLimit(_:)` and/or
  /// `withAttemptLimit(_:)` to bound the retry loop:
  /// ```swift
  /// let policy = StorageBaseRetryPolicy.unbounded()
  ///   .withTimeLimit(.seconds(30))
  ///   .withAttemptLimit(5)
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators,
  ///   this policy retries transient errors indefinitely.
  public static func unbounded() -> StorageBaseRetryPolicy {
    StorageBaseRetryPolicy()
  }

  /// The default retry policy for Google Cloud Storage, with a 60-second time limit and 10-attempt limit.
  public static var defaultPolicy: some RetryPolicy {
    StorageBaseRetryPolicy.unbounded().withTimeLimit(.seconds(60)).withAttemptLimit(10)
  }
}

extension StorageBaseRetryPolicy: RetryPolicy {
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
