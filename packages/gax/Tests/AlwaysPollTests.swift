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

@Suite struct AlwaysPollTests {
  @Test func alwaysPoll() {
    let p = AlwaysPoll()

    #expect(p.onError(state: PollingState(), error: httpUnavailable()) == .retry(httpUnavailable()))
  }

  @Test func alwaysPollErrorKind() {
    let p = AlwaysPoll()

    #expect(p.onError(state: PollingState(), error: .binding("err")) == .retry(.binding("err")))
    #expect(p.onError(state: PollingState(), error: httpUnavailable()) == .retry(httpUnavailable()))
  }

  @Test func alwaysPollOnInProgress() throws {
    let p = AlwaysPoll()
    try p.onInProgress(state: PollingState())
  }

  // Helper functions

  private func httpUnavailable() -> RequestError {
    .http(HTTPDetails(http_status_code: 503, headers: [:], payload: Data()))
  }
}
