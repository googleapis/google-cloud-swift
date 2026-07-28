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

extension LimitedAttemptCount: PollingErrorPolicy where P: PollingErrorPolicy & Sendable {
  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    switch inner.onError(state: state, error: error) {
    case .permanent(let e):
      return .permanent(e)
    case .exhausted(let e):
      return .exhausted(e)
    case .retry(let e):
      if state.attemptCount >= maximumAttempts {
        return .exhausted(e)
      }
      return .retry(e)
    }
  }

  public func onInProgress(state: PollingState) throws {
    try inner.onInProgress(state: state)
  }
}

extension PollingErrorPolicy {
  /// Decorate a `PollingPolicy` to limit the number of retry attempts.
  ///
  /// - Parameter maximumAttempts: The maximum number of attempts allowed by the policy.
  /// - Returns: A decorated retry policy.
  public func withAttemptLimit(_ maximumAttempts: UInt32) -> LimitedAttemptCount<Self> {
    LimitedAttemptCount(inner: self, maximumAttempts: maximumAttempts)
  }
}
