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

/// Implementations of this protocol prevent a client from sending too many retries.
///
/// The client libraries can be configured to automatically retry RPCs. Most often retries are only
/// enabled if (1) the request was never sent and the local error is recoverable, or (2) the failure
/// is a transient errors **and** the RPC is [idempotent].
///
/// Retry strategies that do not throttle themselves can slow down recovery when (a) the service is
/// overloaded, or (b) when recovering from a large incident. This is also known as "retry storms":
/// the retry attempts can grow to be more than the normal traffic and hinder recovery. Note that
/// exponential backoff does not solve this problem: under service overload smearing the retries
/// still keeps the service overloaded.
///
/// Advanced applications may want to configure a retry throttler to [Address Cascading Failures]
/// and when [Handling Overload] conditions. This module contains the traits and some
/// implementations of retry throttling strategies.
///
/// Typically applications should create one retry throttler and share it across multiple clients.
///
/// [idempotent]: https://en.wikipedia.org/wiki/Idempotence
/// [Handling Overload]: https://sre.google/sre-book/handling-overload/
/// [Address Cascading Failures]: https://sre.google/sre-book/addressing-cascading-failures/
public protocol RetryThrottler: Sendable {
  /// Called by the retry loop before issuing a retry attempt.
  ///
  /// - Returns: `true` if the request should be throttled.
  func throttleRetryAttempt() -> Bool

  /// Called by the retry loop after a retry failure.
  ///
  /// - Parameter flow: The result of the retry attempt.
  func onRetryFailure(flow: RetryResult)

  /// Called by the retry loop when a RPC succeeds.
  func onSuccess()
}
