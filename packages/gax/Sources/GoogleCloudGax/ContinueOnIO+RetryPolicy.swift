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

extension ContinueOnIO: RetryPolicy where P: RetryPolicy & Sendable {
  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    if case .io = error {
      return .retry(error)
    }
    return inner.onError(state: state, error: error)
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    inner.onThrottle(state: state, error: error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension RetryPolicy {
  /// Decorate a `RetryPolicy` to continue on I/O errors.
  ///
  /// This policy decorates an inner policy and retries any errors that are I/O errors
  /// **if** the request is idempotent.
  ///
  /// For other errors it returns the same value as the inner policy.
  public func retryOnIO() -> ContinueOnIO<Self> {
    ContinueOnIO(inner: self)
  }
}
