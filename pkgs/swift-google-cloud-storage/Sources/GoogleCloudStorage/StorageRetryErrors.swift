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

import GoogleCloudGax

/// Evaluates whether an error is considered retryable in Google Cloud Storage.
///
/// In Google Cloud Storage, retryable errors include transient HTTP status codes (408, 429, 5xx)
/// and transient gRPC status codes (`unavailable`, `resourceExhausted`, `deadlineExceeded`,
/// and `internal`). The client library must be prepared to retry all of them.
final class StorageRetryErrors: RetryPolicy, Sendable {
  public init() {}

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    if isRetryable(error) {
      return .retry(error)
    }
    return .permanent(error)
  }

  func isRetryable(_ error: RequestError) -> Bool {
    switch error {
    case .http(let details):
      let code = details.httpStatusCode
      return code == 408 || code == 429 || (500...599).contains(code)
    case .service(let details):
      let code = details.code
      return code == .unavailable || code == .resourceExhausted || code == .deadlineExceeded
        || code == .internal
    default:
      return false
    }
  }
}
