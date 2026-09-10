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
import GoogleRpc

/// A retry policy decorator that continues on `ResourceExhausted` or `TOO_MANY_REQUESTS`.
///
/// This policy returns [retry][RetryResult.retry] when the error is a `ResourceExhausted` (or
/// `TOO_MANY_REQUESTS` if received from the HTTP layer). Otherwise it returns the result from the
/// inner retry policy.
public struct TooManyRequests<P: Sendable>: Sendable {
  let inner: P

  public init(inner: P) {
    self.inner = inner
  }

  func isTooManyRequests(_ error: RequestError) -> Bool {
    if case .service(let details) = error {
      return details.code == GoogleRpc.Code.resourceExhausted
    }
    if case .http(let details) = error {
      return details.http_status_code == 429
    }
    return false
  }
}
