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

@Suite struct ResumeStateTests {
  @Test func defaults() {
    let now = ContinuousClock.now
    let state = ResumeState()
    #expect(state.bytesTransferred == 0)
    #expect(state.totalBytes == nil)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
    #expect(state.start >= now)
    #expect(state.lastProgressTime >= now)
  }

  @Test func customInitialization() {
    let start = ContinuousClock.now - .seconds(10)
    let state = ResumeState(bytesTransferred: 2048, totalBytes: 8192, start: start)
    #expect(state.bytesTransferred == 2048)
    #expect(state.totalBytes == 8192)
    #expect(state.consecutiveErrorCount == 0)
    #expect(state.totalResumeCount == 0)
    #expect(state.start == start)
    #expect(state.lastProgressTime == start)
  }

  @Test func with() {
    let start = ContinuousClock.now - .seconds(100)
    let progressTime = ContinuousClock.now - .seconds(10)
    let state = ResumeState().with {
      $0.bytesTransferred = 1024
      $0.totalBytes = 4096
      $0.consecutiveErrorCount = 2
      $0.totalResumeCount = 5
      $0.start = start
      $0.lastProgressTime = progressTime
    }
    #expect(state.bytesTransferred == 1024)
    #expect(state.totalBytes == 4096)
    #expect(state.consecutiveErrorCount == 2)
    #expect(state.totalResumeCount == 5)
    #expect(state.start == start)
    #expect(state.lastProgressTime == progressTime)
  }

  @Test func progressUpdatesState() {
    let policy = StopOnConsecutiveErrors()
    var state = ResumeState().with {
      $0.consecutiveErrorCount = 3
    }

    policy.onProgress(state: &state, bytesAdvanced: 512)
    #expect(state.bytesTransferred == 512)
    #expect(state.consecutiveErrorCount == 0)

    policy.onProgress(state: &state, bytesAdvanced: 256)
    #expect(state.bytesTransferred == 768)
    #expect(state.consecutiveErrorCount == 0)
  }
}
