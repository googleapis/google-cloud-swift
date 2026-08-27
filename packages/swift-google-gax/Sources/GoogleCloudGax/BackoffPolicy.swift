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

/// Defines the protocol implemented by all retry backoff strategies.
///
/// The client libraries automatically retry RPCs based on the ``RetryPolicy`` configured for the
/// request or client. Even when the policy determines that an operation is safe to retry, the
/// client library does not retry failed requests immediately, as (1) the service may need time to
/// recover, and (2) clients often experience simultaneous failures and must avoid coordinated
/// retries that overload the service.
///
/// Application developers use `BackoffPolicy` to configure the delays between retry attempts. The
/// most common implementation of this protocol is ``ExponentialBackoff``, which implements the
/// truncated [exponential backoff] with jitter algorithm.
///
/// Some application may need slight variations on this algorithm, maybe with logging or tracing.
/// Using a policy offers greater flexibility than just a set of configuration parameters.
///
/// [Exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff
/// [idempotent]: https://en.wikipedia.org/wiki/Idempotence
public protocol BackoffPolicy: Sendable {
  /// Returns the backoff delay on a failure.
  ///
  /// - Parameters:
  ///   - state: The current retry state.
  /// - Returns: The delay before the next retry attempt.
  func backoffDelayFor(_ state: RetryState) -> Duration
}
