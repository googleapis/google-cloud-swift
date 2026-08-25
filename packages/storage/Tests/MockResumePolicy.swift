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

struct MockResumePolicy<Details: Sendable>: ResumePolicy {
  var onError: @Sendable (ResumeState<Details>, RequestError) -> ResumeResult = { _, e in
    .permanent(e)
  }
  var onProgress: (@Sendable (inout ResumeState<Details>) -> Void)? = nil
  var remainingTime: @Sendable (ResumeState<Details>) -> Duration? = { _ in nil }

  func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    onError(state, error)
  }

  func onProgress(state: inout ResumeState<Details>) {
    if let custom = onProgress {
      custom(&state)
    } else {
      state.consecutiveErrorCount = 0
      state.lastProgressTime = .now
    }
  }

  func remainingTime(state: ResumeState<Details>) -> Duration? {
    remainingTime(state)
  }
}
