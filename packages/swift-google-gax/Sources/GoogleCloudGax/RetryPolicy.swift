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

/// Determines how errors are handled in the retry loop.
///
/// The client libraries automatically retry RPCs when it is safe, that is when:
/// - the RPC failed before any data for the RPC is sent, or
/// - the error is transient **and** the RPC is [idempotent]
///
/// The retry policy determines what errors are transient, and may limit the number of retry attempts.
///
/// The client libraries offer a number of retry policy implementations, including ``AlwaysRetry``,
/// ``Aip194``, and ``NeverRetry``. In addition, the client libraries offer decorators, such as
/// ``LimitedAttemptCount`` and ``LimitedElapsedTime`` to constraint the number of retry attempts or
/// the duration of the retry loop.
///
/// Application developers may define their own policies if needed.
///
/// [idempotent]: https://en.wikipedia.org/wiki/Idempotence
public protocol RetryPolicy: Sendable {
  /// Query the retry policy after an error.
  ///
  /// - Parameters:
  ///   - state: The state of the retry loop.
  ///   - error: The last error when attempting the request.
  /// - Returns: The result of the retry decision.
  func onError(state: RetryState, error: RequestError) -> RetryResult

  /// Query the retry policy after a retry attempt is throttled.
  ///
  /// Retry attempts may be throttled before they are even sent out. The retry
  /// policy may choose to treat these as normal errors, consuming attempts,
  /// or may prefer to ignore them and always return ``ThrottleResult/retry(_:)``.
  ///
  /// - Parameters:
  ///   - state: The state of the retry loop.
  ///   - error: The previous error that caused the retry attempt. Throttling
  ///     only applies to retry attempts, and a retry attempt implies that a
  ///     previous attempt failed. The retry policy should preserve this error.
  /// - Returns: The result of the throttling decision.
  func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult

  /// The remaining time in the retry policy.
  ///
  /// For policies based on time, this returns the remaining time in the
  /// policy. The retry loop can use this value to adjust the next RPC
  /// timeout. For policies that are not time based this returns `nil`.
  ///
  /// - Parameter state: The state of the retry loop.
  /// - Returns: The remaining time, or `nil` if the policy is not time-based.
  func remainingTime(state: RetryState) -> Duration?
}

extension RetryPolicy {
  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    .retry(error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    nil
  }
}
