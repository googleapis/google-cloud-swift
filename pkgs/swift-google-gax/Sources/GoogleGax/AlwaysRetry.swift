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

/// A retry policy that retries all errors.
///
/// Use ``unbounded()`` decorated with ``RetryPolicy/withTimeLimit(_:)``
/// and/or ``RetryPolicy/withAttemptLimit(_:)`` to configure bounds.
///
/// The policy retries all errors. This may be useful if the service guarantees
/// idempotency, maybe through the use of request ids.
final public class AlwaysRetry: RetryPolicy {
  init() {}

  /// Creates an unconstrained retry policy that retries all errors indefinitely.
  ///
  /// Decorate this policy with ``RetryPolicy/withTimeLimit(_:)`` and/or
  /// ``RetryPolicy/withAttemptLimit(_:)`` to bound the retry loop:
  /// ```swift
  /// let policy = AlwaysRetry.unbounded()
  ///   .withTimeLimit(.seconds(30))
  ///   .withAttemptLimit(5)
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators,
  ///   this policy retries errors indefinitely.
  public static func unbounded() -> AlwaysRetry {
    AlwaysRetry()
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    .retry(error)
  }
}
