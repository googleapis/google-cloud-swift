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

@Suite struct LimitedAttemptCountPollingErrorPolicyTests {
  @Test func testLimitedAttemptCountOnError() {
    let mock = MockPollingPolicy(onError: { _, e in .retry(e) })
    let policy = mock.withAttemptLimit(3)
    let error = transient()

    #expect(
      policy.onError(state: PollingState().with { $0.attemptCount = 1 }, error: error)
        == .retry(error))
    #expect(
      policy.onError(state: PollingState().with { $0.attemptCount = 2 }, error: error)
        == .retry(error))
    #expect(
      policy.onError(state: PollingState().with { $0.attemptCount = 3 }, error: error)
        == .exhausted(error))
  }

  @Test func testLimitedAttemptCountInnerPermanent() {
    let error = permanent()
    let mock = MockPollingPolicy(onError: { _, e in .permanent(e) })
    let policy = mock.withAttemptLimit(2)

    #expect(policy.onError(state: PollingState(), error: error) == .permanent(error))
  }

  @Test func testLimitedAttemptCountInnerExhausted() {
    let error = transient()
    let mock = MockPollingPolicy(onError: { _, e in .exhausted(e) })
    let policy = mock.withAttemptLimit(2)

    #expect(policy.onError(state: PollingState(), error: error) == .exhausted(error))
  }

  @Test func testLimitedAttemptCountOnInProgress() throws {
    let called = Mutex(false)
    let mock = MockPollingPolicy(onInProgress: { _ in
      called.withLock { $0 = true }
    })
    let policy = mock.withAttemptLimit(2)

    try policy.onInProgress(state: PollingState())
    #expect(called.withLock { $0 })
  }

  func transient() -> RequestError {
    RequestError.http(HTTPDetails(http_status_code: 429, headers: [:]))
  }
  func permanent() -> RequestError {
    RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))
  }
}
