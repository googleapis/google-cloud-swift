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

extension ContinueOnIO: PollingErrorPolicy where P: PollingErrorPolicy & Sendable {
  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    if case .io = error {
      return .retry(error)
    }
    return inner.onError(state: state, error: error)
  }

  public func onInProgress(state: PollingState) throws {
    try inner.onInProgress(state: state)
  }
}

extension PollingErrorPolicy {
  /// Decorate a ``PollingErrorPolicy`` to continue on I/O errors.
  ///
  /// This policy decorates an inner policy and retries any errors that are I/O errors
  /// **if** the request is idempotent.
  ///
  /// For other errors it returns the same value as the inner policy.
  public func continueOnIoErrors() -> ContinueOnIO<Self> {
    ContinueOnIO(inner: self)
  }
}
