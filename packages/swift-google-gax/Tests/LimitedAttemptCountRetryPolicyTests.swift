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

@Suite struct LimitedAttemptCountTests {
  @Test func testLimitedAttemptCountOnError() {
    let mock = MockPolicy(onError: { _, e in .retry(e) })
    let policy = mock.withAttemptLimit(3)
    let error = transient()

    #expect(
      policy.onError(state: idempotentState().with { $0.attemptCount = 1 }, error: error)
        == .retry(error))
    #expect(
      policy.onError(state: idempotentState().with { $0.attemptCount = 2 }, error: error)
        == .retry(error))
    #expect(
      policy.onError(state: idempotentState().with { $0.attemptCount = 3 }, error: error)
        == .exhausted(error))
  }

  @Test func testLimitedAttemptCountOnThrottleContinue() {
    let mock = MockPolicy(onThrottle: { _, e in .retry(e) })
    let policy = mock.withAttemptLimit(3)
    let error = transient()

    #expect(
      policy.onThrottle(state: idempotentState().with { $0.attemptCount = 2 }, error: error)
        == .retry(error))
  }

  @Test func testLimitedAttemptCountOnThrottleError() {
    let error = transient()
    let mock = MockPolicy(onThrottle: { _, _ in .exhausted(error) })
    let policy = mock.withAttemptLimit(3)

    #expect(
      policy.onThrottle(state: idempotentState(), error: error) == .exhausted(error))
  }

  @Test func testLimitedAttemptCountRemainingNone() {
    let mock = MockPolicy(remainingTime: { _ in nil })
    let policy = mock.withAttemptLimit(3)

    #expect(policy.remainingTime(state: idempotentState()) == nil)
  }

  @Test func testLimitedAttemptCountRemainingSome() {
    let mock = MockPolicy(remainingTime: { _ in .seconds(123) })
    let policy = mock.withAttemptLimit(3)

    #expect(policy.remainingTime(state: idempotentState()) == .seconds(123))
  }

  @Test func testLimitedAttemptCountInnerPermanent() {
    let error = permanent()
    let mock = MockPolicy(onError: { _, e in .permanent(e) })
    let policy = mock.withAttemptLimit(2)

    #expect(policy.onError(state: nonIdempotentState(), error: error) == .permanent(error))
    #expect(policy.onError(state: nonIdempotentState(), error: error) == .permanent(error))
  }

  @Test func testLimitedAttemptCountInnerExhausted() {
    let error = transient()
    let mock = MockPolicy(onError: { _, e in .exhausted(e) })
    let policy = mock.withAttemptLimit(2)

    #expect(policy.onError(state: nonIdempotentState(), error: error) == .exhausted(error))
    #expect(policy.onError(state: nonIdempotentState(), error: error) == .exhausted(error))
  }

  func transient() -> RequestError {
    RequestError.http(HTTPDetails(http_status_code: 429, headers: [:]))
  }
  func permanent() -> RequestError {
    RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))
  }
}
