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
import Synchronization
import Testing

@Suite struct TooManyRequestsPollingErrorPolicyTests {
  @Test func testTooManyRequestsOnError() {
    let mock = MockPollingPolicy(onError: { _, e in .permanent(e) })
    let policy = mock.continueOnTooManyRequests()

    #expect(
      policy.onError(state: PollingState(), error: tooManyRequests()) == .retry(tooManyRequests()))
    #expect(
      policy.onError(state: PollingState(), error: tooManyRequestsHttp())
        == .retry(tooManyRequestsHttp()))
    #expect(policy.onError(state: PollingState(), error: permanent()) == .permanent(permanent()))
  }

  @Test func testTooManyRequestsOnInProgress() throws {
    let called = Mutex(false)
    let mock = MockPollingPolicy(onInProgress: { _, _ in
      called.withLock { $0 = true }
    })
    let policy = mock.continueOnTooManyRequests()

    try policy.onInProgress(state: PollingState(), name: "op-name")
    #expect(called.withLock { $0 })
  }

  // Helper functions

  private func tooManyRequests() -> RequestError {
    .service(
      ServiceError(code: GoogleRpc.Code.resourceExhausted, message: "RESOURCE_EXHAUSTED")
    )
  }

  private func tooManyRequestsHttp() -> RequestError {
    .http(HTTPDetails(http_status_code: 429, headers: [:], payload: Data()))
  }

  private func permanent() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.permissionDenied, message: "PERMISSION_DENIED"))
  }
}
