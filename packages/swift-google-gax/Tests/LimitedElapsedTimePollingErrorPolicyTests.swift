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
import Synchronization
import Testing

@Suite struct LimitedElapsedTimePollingErrorPolicyTests {
  @Test func testLimitedTimeInnerContinues() {
    let mock = MockPollingPolicy(onError: { _, e in .retry(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)
    let error = mockIOError()

    let stateBefore = PollingState().with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .retry(error))

    let stateAfter = PollingState().with {
      $0.start = .now - .seconds(70)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .exhausted(error))
  }

  @Test func testLimitedTimeInnerPermanent() {
    let error = mockIOError()
    let mock = MockPollingPolicy(onError: { _, e in .permanent(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let stateBefore = PollingState().with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .permanent(error))

    let stateAfter = PollingState().with {
      $0.start = .now + .seconds(10)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .permanent(error))
  }

  @Test func testLimitedTimeInnerExhausted() {
    let error = mockIOError()
    let mock = MockPollingPolicy(onError: { _, e in .exhausted(e) })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    let stateBefore = PollingState().with {
      $0.start = .now - .seconds(10)
    }
    #expect(policy.onError(state: stateBefore, error: error) == .exhausted(error))

    let stateAfter = PollingState().with {
      $0.start = .now + .seconds(10)
    }
    #expect(policy.onError(state: stateAfter, error: error) == .exhausted(error))
  }

  @Test func testLimitedTimeOnInProgress() throws {
    let called = Mutex(false)
    let mock = MockPollingPolicy(onInProgress: { _ in
      called.withLock { $0 = true }
    })
    let limit = Duration.seconds(60)
    let policy = mock.withTimeLimit(limit)

    try policy.onInProgress(state: PollingState())
    #expect(called.withLock { $0 })
  }
}
