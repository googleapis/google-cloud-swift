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

@Suite struct TooManyRequestsTests {
  @Test func testTooManyRequestsOnError() {
    let policy = NeverRetry().retryOnTooManyRequests()
    let state = RetryState(idempotent: true)

    #expect(policy.onError(state: state, error: tooManyRequests()) == .retry(tooManyRequests()))
    #expect(
      policy.onError(state: state, error: tooManyRequestsHttp()) == .retry(tooManyRequestsHttp()))
    #expect(policy.onError(state: state, error: permanent()) == .exhausted(permanent()))
  }

  @Test func testTooManyRequestsExt() {
    let policy = NeverRetry().retryOnTooManyRequests()
    let state = RetryState(idempotent: true)

    #expect(policy.onError(state: state, error: tooManyRequests()) == .retry(tooManyRequests()))
    #expect(
      policy.onError(state: state, error: tooManyRequestsHttp()) == .retry(tooManyRequestsHttp()))
    #expect(policy.onError(state: state, error: permanent()) == .exhausted(permanent()))
  }

  @Test func testTooManyRequestsForwards() {
    let mock = MockPolicy(
      onError: { _, e in .permanent(e) },
      onThrottle: { _, e in .exhausted(e) },
      remainingTime: { _ in nil }
    )

    let policy = TooManyRequests(inner: mock)
    let state = RetryState(idempotent: true)

    #expect(policy.onError(state: state, error: transient()) == .permanent(transient()))
    #expect(policy.onError(state: state, error: tooManyRequests()) == .retry(tooManyRequests()))

    #expect(policy.onThrottle(state: state, error: transient()) == .exhausted(transient()))
    #expect(
      policy.onThrottle(state: state, error: tooManyRequests()) == .exhausted(tooManyRequests()))

    #expect(policy.remainingTime(state: state) == nil)
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

  private func transient() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))
  }
}
