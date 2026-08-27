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

struct MockPolicy: RetryPolicy {
  var onError: @Sendable (RetryState, RequestError) -> RetryResult = { _, e in .permanent(e) }
  var onThrottle: @Sendable (RetryState, RequestError) -> ThrottleResult = { _, e in .retry(e) }
  var remainingTime: @Sendable (RetryState) -> Duration? = { _ in nil }

  func onError(state: RetryState, error: RequestError) -> RetryResult {
    onError(state, error)
  }

  func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    onThrottle(state, error)
  }

  func remainingTime(state: RetryState) -> Duration? {
    remainingTime(state)
  }
}

func idempotentState() -> RetryState {
  RetryState(idempotent: true)
}

func nonIdempotentState() -> RetryState {
  RetryState(idempotent: false)
}

func mockIOError() -> RequestError {
  // The inner error is not important for the tests.
  RequestError.io(RequestError.unimplemented)
}
