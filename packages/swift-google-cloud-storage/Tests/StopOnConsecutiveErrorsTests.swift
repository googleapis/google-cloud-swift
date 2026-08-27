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

@Suite struct StopOnConsecutiveErrorsTests {
  @Test func defaultsAndDelegation() {
    let mock = MockResumePolicy<Void>(onError: { _, e in .resume(e) })
    let policy = mock.stopOnConsecutiveErrors(3)
    #expect(policy.maxConsecutiveErrors == 3)
    #expect(policy.remainingTime(state: ResumeState()) == nil)
  }

  @Test func consecutiveLimitReached() {
    let mock = MockResumePolicy<Void>(onError: { _, e in .resume(e) })
    let policy = mock.stopOnConsecutiveErrors(2)
    var state = ResumeState()
    let error = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))

    // 0 errors -> resumes
    #expect(policy.onError(state: state, error: error) == .resume(error))

    // 1 error -> resumes
    state.consecutiveErrorCount = 1
    #expect(policy.onError(state: state, error: error) == .resume(error))

    // 2 errors -> exhausted
    state.consecutiveErrorCount = 2
    #expect(policy.onError(state: state, error: error) == .exhausted(error))

    // 3 errors -> exhausted
    state.consecutiveErrorCount = 3
    #expect(policy.onError(state: state, error: error) == .exhausted(error))
  }

  @Test func innerPermanentPassesThrough() {
    let permanentError = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))
    let mock = MockResumePolicy<Void>(onError: { _, e in .permanent(e) })
    let policy = mock.stopOnConsecutiveErrors(5)
    let state = ResumeState()

    #expect(policy.onError(state: state, error: permanentError) == .permanent(permanentError))
  }

  @Test func innerExhaustedPassesThrough() {
    let exhaustedError = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let mock = MockResumePolicy<Void>(onError: { _, e in .exhausted(e) })
    let policy = mock.stopOnConsecutiveErrors(5)
    let state = ResumeState()

    #expect(policy.onError(state: state, error: exhaustedError) == .exhausted(exhaustedError))
  }

  @Test func progressForwardsToInner() {
    let mock = MockResumePolicy<Void>(
      onError: { _, e in .resume(e) },
      onProgress: { state in
        state.consecutiveErrorCount = 0
      }
    )
    let policy = mock.stopOnConsecutiveErrors(3)
    var state = ResumeState().with { $0.consecutiveErrorCount = 2 }

    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)
  }

  @Test func remainingTimeForwardsToInner() {
    let mock = MockResumePolicy<Void>(
      onError: { _, e in .resume(e) },
      remainingTime: { _ in .seconds(42) }
    )
    let policy = mock.stopOnConsecutiveErrors(3)
    let state = ResumeState()

    #expect(policy.remainingTime(state: state) == .seconds(42))
  }
}
