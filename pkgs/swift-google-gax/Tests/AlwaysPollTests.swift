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
import Testing

@Suite struct AlwaysPollTests {
  @Test func alwaysPoll() {
    let p = AlwaysPoll.unbounded()

    #expect(p.onError(state: PollingState(), error: httpUnavailable()) == .retry(httpUnavailable()))
  }

  @Test func alwaysPollErrorKind() {
    let p = AlwaysPoll.unbounded()

    #expect(
      p.onError(state: PollingState(), error: .binding(BindingError()))
        == .retry(.binding(BindingError())))
    #expect(p.onError(state: PollingState(), error: httpUnavailable()) == .retry(httpUnavailable()))
  }

  @Test func alwaysPollOnInProgress() throws {
    let p = AlwaysPoll.unbounded()
    try p.onInProgress(state: PollingState())
  }

  @Test func equatable() {
    let a = AlwaysPoll()
    let b = AlwaysPoll.unbounded()
    #expect(a == b)
  }

  // Helper functions

  private func httpUnavailable() -> RequestError {
    .http(HTTPDetails(httpStatusCode: 503, headers: [:], payload: Data()))
  }
}
