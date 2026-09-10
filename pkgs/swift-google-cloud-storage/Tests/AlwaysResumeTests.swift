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
import GoogleCloudStorage
import Testing

@Suite struct AlwaysResumeTests {
  @Test func alwaysResume() {
    let policy = AlwaysResume<Void>()
    var state = ResumeState()
    let error503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let error400 = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))
    let errorBinding = RequestError.binding("test error")

    #expect(policy.onError(state: state, error: error400) == .resume(error400))
    #expect(policy.onError(state: state, error: errorBinding) == .resume(errorBinding))

    state.consecutiveErrorCount = 50
    state.totalResumeCount = 500
    #expect(policy.onError(state: state, error: error503) == .resume(error503))
    #expect(policy.remainingTime(state: state) == nil)
  }

  @Test func staticFactory() {
    let policy: AlwaysResume<Void> = .always()
    let state = ResumeState()
    let transient503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    #expect(policy.onError(state: state, error: transient503) == .resume(transient503))
  }
}
