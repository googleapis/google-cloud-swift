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

/// A retry policy for BigQuery that retries transient errors on idempotent requests.
///
/// This policy retries idempotent requests that fail with I/O errors, with the HTTP status codes
/// 429, 500, 502, 503, or 504, or with one of the error reasons `rateLimitExceeded`,
/// `backendError`, `internalError`, or `badGateway`.
///
/// Use ``defaultPolicy`` for the standard bounded configuration (a 50-second time limit and a
/// 6-attempt limit), or ``unbounded()`` decorated with `withTimeLimit(_:)` and/or
/// `withAttemptLimit(_:)` to configure custom limits.
public struct BigQueryRetryPolicy: Sendable, Equatable {
  let inner: StrictIdempotency<ContinueOnIO<BigQueryRetryErrors>>

  /// Creates a policy without attempt or time limits.
  public init() {
    self.inner = BigQueryRetryErrors().retryOnIO().strictIdempotency()
  }

  /// Creates a BigQuery retry policy without attempt or time limits.
  ///
  /// Decorate this policy with `withTimeLimit(_:)` and/or `withAttemptLimit(_:)` to bound the
  /// retry loop:
  /// ```swift
  /// let policy = BigQueryRetryPolicy.unbounded()
  ///   .withTimeLimit(.seconds(30))
  ///   .withAttemptLimit(5)
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators, this policy
  ///   retries transient errors indefinitely.
  public static func unbounded() -> BigQueryRetryPolicy {
    BigQueryRetryPolicy()
  }

  /// The default retry policy for BigQuery, with a 50-second time limit and a 6-attempt limit.
  public static var defaultPolicy: some RetryPolicy {
    BigQueryRetryPolicy.unbounded().withTimeLimit(.seconds(50)).withAttemptLimit(6)
  }
}

extension BigQueryRetryPolicy: RetryPolicy {
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

/// Classifies the errors BigQuery considers transient.
struct BigQueryRetryErrors: RetryPolicy, Sendable, Equatable {
  /// The HTTP status codes that are always retryable.
  static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

  /// The `error.errors[].reason` values that are retryable whatever the status code.
  static let retryableReasons: Set<String> = [
    "rateLimitExceeded", "backendError", "internalError", "badGateway",
  ]

  func onError(state: RetryState, error: RequestError) -> RetryResult {
    self.isRetryable(error) ? .retry(error) : .permanent(error)
  }

  func isRetryable(_ error: RequestError) -> Bool {
    guard case .http(let details) = error else { return false }
    if Self.retryableStatusCodes.contains(details.statusCode) { return true }
    let reasons = ErrorBody.parse(details.payload)?.error.errors?.compactMap(\.reason) ?? []
    return reasons.contains { Self.retryableReasons.contains($0) }
  }
}
