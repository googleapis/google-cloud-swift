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

/// Defines the protocol implemented by all LRO polling backoff strategies.
///
/// The client libraries can automatically poll long-running operations (LROs) until completion.
/// When doing so, they wait between polling attempts to avoid overloading the service.
///
/// These policies are distinct from retry ``BackoffPolicy`` implementations. Notably, polling
/// backoff policies typically do not use jitter, whereas retry backoff policies do.
///
/// Application developers use `PollingBackoffPolicy` to configure the delays between polling
/// attempts. The most common implementation is ``ExponentialBackoff``, which implements truncated
/// [exponential backoff] without jitter when used as a polling backoff policy.
///
/// [Exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff
public protocol PollingBackoffPolicy: Sendable {
  /// Returns the backoff delay before the next polling attempt.
  ///
  /// - Parameters:
  ///   - state: The current polling state.
  /// - Returns: The delay before the next polling attempt.
  func backoffDelayFor(_ state: PollingState) -> Duration
}
