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
import GoogleCloudStorage
import Testing

@Suite struct ResumeStateTests {
  @Test func defaults() {
    let now = ContinuousClock.now
    let state = ResumeState()
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
    #expect(state.start >= now)
    #expect(state.lastProgressTime >= now)
  }

  @Test func customInitialization() {
    let start = ContinuousClock.now - .seconds(10)
    let state = ResumeState(start: start)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
    #expect(state.start == start)
    #expect(state.lastProgressTime == start)
  }

  @Test func with() {
    let start = ContinuousClock.now - .seconds(100)
    let progressTime = ContinuousClock.now - .seconds(10)
    let state = ResumeState().with {
      $0.consecutiveErrorCount = 2
      $0.totalResumeCount = 5
      $0.start = start
      $0.lastProgressTime = progressTime
    }
    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 5)
    #expect(state.start == start)
    #expect(state.lastProgressTime == progressTime)
  }

  @Test func progressUpdatesState() {
    let policy = AlwaysResume<Void>()
    var state = ResumeState().with {
      $0.consecutiveErrorCount = 3
    }

    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)

    state.consecutiveErrorCount = 2
    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)
  }

  @Test func genericDetails() {
    struct CustomDetails: Sendable, Equatable {
      var bytes: UInt64
    }

    var state = ResumeState(details: CustomDetails(bytes: 1024))
    #expect(state.details.bytes == 1024)
    #expect(state.consecutiveErrorCount == 0)

    let policy = AlwaysResume<CustomDetails>()
    state.consecutiveErrorCount = 4
    policy.onProgress(state: &state)
    #expect(state.consecutiveErrorCount == 0)

    var copy = ResumeState(details: CustomDetails(bytes: 1024), start: state.start)
    copy.lastProgressTime = state.lastProgressTime
    #expect(state == copy)
  }
}
