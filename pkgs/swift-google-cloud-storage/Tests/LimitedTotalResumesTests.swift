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

import GoogleGax
import Testing
@testable import GoogleCloudStorage

@Suite struct LimitedTotalResumesTests {
  /// Verifies the default total resume threshold (10) and `remainingTime` delegation.
  @Test func defaultsAndDelegation() {
    let mock = MockResumePolicy<Void>(onError: { _, e in .resume(e) })
    let policy = mock.withTotalResumeLimit()
    #expect(policy.maxTotalResumes == 10)
    #expect(policy.remainingTime(state: ResumeState()) == nil)
  }

  @Test func totalResumeLimit() {
    let mock = MockResumePolicy<Void>(onError: { _, e in .resume(e) })
    let policy = mock.withTotalResumeLimit(2)
    var state = ResumeState()
    let error = RequestError.http(HTTPDetails(statusCode: 503, headers: []))

    // 0 resumes
    #expect(policy.onError(state: state, error: error) == .resume(error))

    // 1st attempt resumes
    state.totalResumeCount = 1
    #expect(policy.onError(state: state, error: error) == .resume(error))

    // Making progress doesn't reset total resumes
    policy.onProgress(state: &state)
    #expect(state.totalResumeCount == 1)

    // 2nd attempt exhausts
    state.totalResumeCount = 2
    #expect(policy.onError(state: state, error: error) == .exhausted(error))

    // 3rd attempt exhausts
    state.totalResumeCount = 3
    #expect(policy.onError(state: state, error: error) == .exhausted(error))
  }

  @Test func innerPermanentPassesThrough() {
    let permanentError = RequestError.http(HTTPDetails(statusCode: 403, headers: []))
    let mock = MockResumePolicy<Void>(onError: { _, e in .permanent(e) })
    let policy = mock.withTotalResumeLimit(5)

    #expect(
      policy.onError(state: ResumeState(), error: permanentError) == .permanent(permanentError))
    #expect(
      policy.onError(
        state: ResumeState(totalResumeCount: 5),
        error: permanentError
      ) == .permanent(permanentError)
    )
  }

  @Test func innerExhaustedPassesThrough() {
    let exhaustedError = RequestError.http(HTTPDetails(statusCode: 503, headers: []))
    let mock = MockResumePolicy<Void>(onError: { _, e in .exhausted(e) })
    let policy = mock.withTotalResumeLimit(5)
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
    let policy = mock.withTotalResumeLimit(3)
    var state = ResumeState().with { $0.consecutiveErrorCount = 2 }

    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)
  }

  @Test func remainingTimeForwardsToInner() {
    let mock = MockResumePolicy<Void>(
      onError: { _, e in .resume(e) },
      remainingTime: { _ in .seconds(42) }
    )
    let policy = mock.withTotalResumeLimit(3)
    let state = ResumeState()

    #expect(policy.remainingTime(state: state) == .seconds(42))
  }

  @Test func clampingZeroAndNegativeLimits() {
    let mock = MockResumePolicy<Void>(onError: { _, e in .resume(e) })
    let policyZero = mock.withTotalResumeLimit(0)
    #expect(policyZero.maxTotalResumes == 0)

    let policyNegative = mock.withTotalResumeLimit(-5)
    #expect(policyNegative.maxTotalResumes == 0)

    let error = RequestError.http(HTTPDetails(statusCode: 503, headers: []))
    let state = ResumeState()

    #expect(policyZero.onError(state: state, error: error) == .exhausted(error))
    #expect(policyNegative.onError(state: state, error: error) == .exhausted(error))
  }

  @Test func equatable() {
    let a = AlwaysResume<Void>.unbounded().withTotalResumeLimit(10)
    let b = AlwaysResume<Void>.unbounded().withTotalResumeLimit()
    #expect(a == b)

    let c = AlwaysResume<Void>.unbounded().withTotalResumeLimit(5)
    #expect(a != c)
  }

  /// Verifies `Details` associated-type forwarding for non-`Void` transfer details.
  @Test func forwardsNonVoidDetailsType() {
    let mock = MockResumePolicy<WriteObjectDetails>(
      onError: { state, e in
        state.details.bytesWritten > 0 ? .resume(e) : .permanent(e)
      }
    )
    let policy: any ResumePolicy<WriteObjectDetails> = mock.withTotalResumeLimit(2)
    let error = RequestError.http(HTTPDetails(statusCode: 503, headers: []))

    let progressedState = ResumeState(
      details: WriteObjectDetails(bytesWritten: 512, totalBytes: 1024),
      totalResumeCount: 1
    )
    #expect(policy.onError(state: progressedState, error: error) == .resume(error))
  }
}
