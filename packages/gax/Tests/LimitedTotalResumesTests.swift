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

@Suite struct LimitedTotalResumesTests {
  @Test func defaults() {
    let policy = LimitedTotalResumes()
    #expect(policy.maxTotalResumes == 10)
    #expect(policy.remainingTime(state: ResumeState()) == nil)
  }

  @Test func staticFactories() {
    let customPolicy: LimitedTotalResumes = .limitedTotalResumes(5)
    #expect(customPolicy.maxTotalResumes == 5)
  }

  @Test func totalResumeLimit() {
    let policy = LimitedTotalResumes(maxTotalResumes: 2)
    let state = ResumeState()
    let transient503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let permanent403 = RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))

    // Permanent error halts immediately
    #expect(policy.onError(state: state, error: permanent403) == .permanent(permanent403))

    // 1st attempt resumes
    state.totalResumeCount = 1
    #expect(policy.onError(state: state, error: transient503) == .resume(transient503))

    // Making progress doesn't reset total resumes
    policy.onProgress(state: state)
    #expect(state.totalResumeCount == 1)

    // 2nd attempt exhausts
    state.totalResumeCount = 2
    #expect(policy.onError(state: state, error: transient503) == .exhausted(transient503))
  }
}
