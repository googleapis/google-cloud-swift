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
import GoogleRpc
import Synchronization
import Testing

private struct MockBackoff: BackoffPolicy {
  var delay: Duration = .zero
  func backoffDelayFor(_ state: RetryState) -> Duration { delay }
}

@Suite struct ResumeLoopTests {
  private func permanentError() -> RequestError {
    RequestError.service(ServiceError(code: Code.permissionDenied, message: "permission denied"))
  }

  private func transientError() -> RequestError {
    RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
  }

  @Test func immediateSuccess() async throws {
    let loop = _ResumeLoop(
      resumePolicy: AlwaysResume<Void>().stopOnConsecutiveErrors(),
      backoffPolicy: MockBackoff()
    )

    let response = try await loop.run(
      attempt: { _ in "success" },
      sleep: { _ in }
    )

    #expect(response == "success")
  }

  @Test func transientFailureThenSuccess() async throws {
    let loop = _ResumeLoop(
      resumePolicy: AlwaysResume<Void>().stopOnConsecutiveErrors(3),
      backoffPolicy: MockBackoff(delay: .milliseconds(10))
    )

    let attempts = Mutex<Int>(0)
    var state = ResumeState()

    let response = try await loop.run(
      state: &state,
      attempt: { _ in
        let count = attempts.withLock { count in
          count += 1
          return count
        }
        if count < 3 {
          throw self.transientError()
        }
        return "success"
      },
      sleep: { _ in }
    )

    #expect(response == "success")
    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 2)
  }

  @Test func permanentErrorThrows() async throws {
    let loop = _ResumeLoop(
      resumePolicy: NeverResume<Void>(),
      backoffPolicy: MockBackoff()
    )

    var state = ResumeState()
    let err = permanentError()

    await #expect(throws: RequestError.self) {
      try await loop.run(
        state: &state,
        attempt: { _ in
          throw err
        },
        sleep: { _ in }
      )
    }
  }

  @Test func exhaustedConsecutiveErrorsThrows() async throws {
    let loop = _ResumeLoop(
      resumePolicy: AlwaysResume<Void>().stopOnConsecutiveErrors(2),
      backoffPolicy: MockBackoff()
    )

    var state = ResumeState()
    let err = transientError()

    await #expect(throws: RequestError.self) {
      try await loop.run(
        state: &state,
        attempt: { _ in
          throw err
        },
        sleep: { _ in }
      )
    }

    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 2)
  }

  @Test func handleErrorAndProgress() async throws {
    let loop = _ResumeLoop(
      resumePolicy: AlwaysResume<Void>().stopOnConsecutiveErrors(2),
      backoffPolicy: MockBackoff(delay: .milliseconds(10))
    )

    var state = ResumeState()
    let sleepCount = Mutex<Int>(0)

    // 1st transient error handled
    try await loop.handleError(
      state: &state, error: transientError(),
      sleep: { _ in
        sleepCount.withLock { $0 += 1 }
      })
    #expect(state.consecutiveErrorCount == 1)
    #expect(state.totalResumeCount == 1)
    #expect(sleepCount.withLock { $0 } == 1)

    // Making progress resets consecutive error count
    loop.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 1)

    // Error after progress is now count 1
    try await loop.handleError(
      state: &state, error: transientError(),
      sleep: { _ in
        sleepCount.withLock { $0 += 1 }
      })
    #expect(state.consecutiveErrorCount == 1)
    #expect(state.totalResumeCount == 2)
  }
}
