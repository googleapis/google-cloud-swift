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
import GoogleGax
import GoogleRpc
import Testing

@Suite struct AIP194PollingErrorPolicyTests {
  @Test(
    "Verify AIP194 retries retryable errors for polling",
    arguments: [
      unavailable(),
      unknownAnd503(),
      httpUnavailable(),
    ])
  func onRetryable(e: RequestError) {
    let p: any PollingErrorPolicy = AIP194.unbounded()
    #expect(p.onError(state: PollingState(), error: e) == PollingResult.retry(e))
  }

  @Test(
    "Verify AIP194 stops permanent errors for polling",
    arguments: [
      permissionDenied(),
      httpPermissionDenied(),
    ]
  )
  func onPermanent(e: RequestError) {
    let p: any PollingErrorPolicy = AIP194.unbounded()
    #expect(p.onError(state: PollingState(), error: e) == PollingResult.permanent(e))
  }

  @Test("Verify AIP194 onInProgress continues")
  func onInProgress() {
    let p: any PollingErrorPolicy = AIP194.unbounded()
    #expect(p.onInProgress(state: PollingState()) == .keepPolling)
  }

  static func unavailable() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))
  }

  static func unknownAnd503() -> RequestError {
    // Some services return a status of "Unknown" and a http status code of 503
    .http(HTTPDetails(statusCode: 503, headers: [], payload: Data()))
  }

  static func permissionDenied() -> RequestError {
    .service(
      ServiceError(code: GoogleRpc.Code.permissionDenied, message: "PERMISSION_DENIED"))
  }

  static func httpUnavailable() -> RequestError {
    .http(HTTPDetails(statusCode: 503, headers: [], payload: Data()))
  }

  static func httpPermissionDenied() -> RequestError {
    .http(HTTPDetails(statusCode: 403, headers: [], payload: Data()))
  }
}
