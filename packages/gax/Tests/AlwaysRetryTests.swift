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
import Testing

@Suite struct AlwaysRetryTests {
  @Test func alwaysRetry() {
    let p = AlwaysRetry()

    #expect(
      p.onError(state: idempotentState(), error: httpUnavailable()) == .retry(httpUnavailable()))
    #expect(
      p.onError(state: nonIdempotentState(), error: httpUnavailable()) == .retry(httpUnavailable()))

    #expect(p.remainingTime(state: idempotentState()) == nil)
  }

  @Test(arguments: [true, false])
  func alwaysRetryErrorKind(idempotent: Bool) {
    let p = AlwaysRetry()
    let state = idempotent ? idempotentState() : nonIdempotentState()

    #expect(p.onError(state: state, error: .binding("err")) == .retry(.binding("err")))
    #expect(p.onError(state: state, error: httpUnavailable()) == .retry(httpUnavailable()))
  }

  // Helper functions

  private func httpUnavailable() -> RequestError {
    .http(HTTPDetails(http_status_code: 503, headers: [:], payload: Data()))
  }
}
