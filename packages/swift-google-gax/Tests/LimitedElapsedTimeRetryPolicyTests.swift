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

@Suite struct LimitedElapsedTimeTests {
  @Test func limitedElapsedTimeError() {
    let limit = Duration.seconds(123) + .milliseconds(567)
    let source = mockIOError()
    let err = LimitedElapsedTimeError(maximumDuration: limit, source: source)
    #expect(err.maximumDuration == limit)
    #expect(err.source == source)
  }

  @Test func testLimitedTimeForwards() {
    let mock = MockPolicy(
      onError: { _, e in .retry(e) },
      onThrottle: { _, e in .retry(e) },
      remainingTime: { _ in nil }
    )

    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)
    let state = RetryState(idempotent: true)
    let error = mockIOError()

    #expect(policy.onError(state: state, error: error) == .retry(error))
    #expect(policy.remainingTime(state: state) != nil)
    #expect(policy.onThrottle(state: state, error: error) == .retry(error))
  }

  @Test func testLimitedTimeOnThrottleContinue() {
    let mock = MockPolicy(onThrottle: { _, e in .retry(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    // Before the policy expires the inner result is returned verbatim.
    let stateBefore = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(50)
    }
    let error = mockIOError()
    #expect(policy.onThrottle(state: stateBefore, error: error) == .retry(error))

    // After the policy expires the inner result is always "exhausted".
    let stateAfter = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(70)
    }
    let expectedError = RequestError.exhausted(
      LimitedElapsedTimeError(maximumDuration: limit, source: error))
    #expect(policy.onThrottle(state: stateAfter, error: error) == .exhausted(expectedError))
  }

  @Test func testLimitedTimeOnThrottleExhausted() {
    let error = mockIOError()
    let mock = MockPolicy(onThrottle: { _, _ in .exhausted(error) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    // Before the policy expires the inner result is returned verbatim.
    let stateBefore = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(50)
    }
    #expect(policy.onThrottle(state: stateBefore, error: error) == .exhausted(error))
  }

  @Test func testLimitedTimeInnerContinues() {
    let mock = MockPolicy(onError: { _, e in .retry(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)
    let error = mockIOError()

    let stateBefore = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .retry(error))

    let stateAfter = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(70)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .exhausted(error))
  }

  @Test func testLimitedTimeInnerPermanent() {
    let error = mockIOError()
    let mock = MockPolicy(onError: { _, e in .permanent(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let stateBefore = RetryState(idempotent: false).with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .permanent(error))

    let stateAfter = RetryState(idempotent: false).with {
      $0.start = .now + .seconds(10)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .permanent(error))
  }

  @Test func testLimitedTimeInnerExhausted() {
    let error = mockIOError()
    let mock = MockPolicy(onError: { _, e in .exhausted(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let stateBefore = RetryState(idempotent: false).with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .exhausted(error))

    let stateAfter = RetryState(idempotent: false).with {
      $0.start = .now + .seconds(10)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .exhausted(error))
  }

  @Test func testLimitedTimeRemainingInnerLonger() {
    let mock = MockPolicy(remainingTime: { _ in .seconds(30) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let state = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(55)
    }
    let remaining = policy.remainingTime(state: state)
    #expect(remaining != nil)
    if let remaining = remaining {
      #expect(remaining <= .seconds(5))
    }
  }

  @Test func testLimitedTimeRemainingInnerShorter() {
    let mock = MockPolicy(remainingTime: { _ in .seconds(5) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let state = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(5)
    }
    let remaining = policy.remainingTime(state: state)
    #expect(remaining != nil)
    if let remaining = remaining {
      #expect(remaining <= .seconds(10))
    }
  }

  @Test func testLimitedTimeRemainingInnerIsNone() {
    let mock = MockPolicy(remainingTime: { _ in nil })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let state = RetryState(idempotent: true).with {
      $0.start = .now - .seconds(50)
    }
    let remaining = policy.remainingTime(state: state)
    #expect(remaining != nil)
    if let remaining = remaining {
      #expect(remaining <= .seconds(10))
    }
  }
}
