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

extension TooManyRequests: PollingErrorPolicy where P: PollingErrorPolicy {
  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    if isTooManyRequests(error) {
      return .retry(error)
    }
    return inner.onError(state: state, error: error)
  }

  public func onInProgress(state: PollingState) throws {
    try inner.onInProgress(state: state)
  }
}

extension PollingErrorPolicy {
  /// Decorate a ``PollingErrorPolicy`` to continue on certain status codes.
  ///
  /// This policy decorates an inner policy and continues on errors with HTTP status code
  /// "429 - TOO_MANY_REQUESTS" **or** where the service returns an error with code
  /// `ResourceExhausted`.
  ///
  /// For other errors it returns the same value as the inner policy.
  public func continueOnTooManyRequests() -> TooManyRequests<Self> {
    TooManyRequests(inner: self)
  }
}
