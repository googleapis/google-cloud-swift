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

/// The result of a polling loop control decision.
///
/// Application developers only need to use this type when implementing their own polling policies.
public enum PollingResult: Sendable {
  /// The error is non-retryable, stop the loop.
  case permanent(RequestError)

  /// The error is retryable, but the policy is stopping the loop.
  ///
  /// Polling policies may stop the loop on retryable errors. For example, because the policy only
  /// allows a limited number of attempts.
  case exhausted(RequestError)

  /// The error was retryable, continue the loop.
  case retry(RequestError)
}
