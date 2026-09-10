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
import GoogleCloudGax
import GoogleRpc
import Testing

@Suite struct BaseRetryPolicyTests {
  @Test(
    "Verify BaseRetryPolicy retries retryable errors",
    arguments: [
      unavailable(),
      unknownAnd503(),
      httpUnavailable(),
    ])
  func onRetryable(e: RequestError) {
    let p = BaseRetryPolicy()
    #expect(p.onError(state: idempotentState(), error: e) == .retry(e))
    #expect(p.onError(state: nonIdempotentState(), error: e) == .permanent(e))
    #expect(p.onThrottle(state: idempotentState(), error: e) == .retry(e))
    #expect(p.onThrottle(state: nonIdempotentState(), error: e) == .exhausted(e))
    #expect(p.remainingTime(state: idempotentState()) == nil)
    #expect(p.remainingTime(state: nonIdempotentState()) == nil)
  }

  @Test(
    "Verify Aip194 stops permanent errors",
    arguments: [
      permissionDenied(),
      httpPermissionDenied(),
    ]
  )
  func onPermanent(e: RequestError) {
    let p = BaseRetryPolicy()
    #expect(p.onError(state: idempotentState(), error: e) == .permanent(e))
    #expect(p.onError(state: nonIdempotentState(), error: e) == .permanent(e))
    #expect(p.onThrottle(state: idempotentState(), error: e) == .retry(e))
    #expect(p.onThrottle(state: nonIdempotentState(), error: e) == .exhausted(e))
    #expect(p.remainingTime(state: idempotentState()) == nil)
    #expect(p.remainingTime(state: nonIdempotentState()) == nil)
  }

  static func unavailable() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))
  }

  static func unknownAnd503() -> RequestError {
    // Some services return a status of "Unknown" and a http status code of 503
    .http(HTTPDetails(http_status_code: 503, headers: [:], payload: Data()))
  }

  static func permissionDenied() -> RequestError {
    .service(
      ServiceError(code: GoogleRpc.Code.permissionDenied, message: "PERMISSION_DENIED"))
  }

  static func httpUnavailable() -> RequestError {
    .http(HTTPDetails(http_status_code: 503, headers: [:], payload: Data()))
  }

  static func httpPermissionDenied() -> RequestError {
    .http(HTTPDetails(http_status_code: 403, headers: [:], payload: Data()))
  }
}
