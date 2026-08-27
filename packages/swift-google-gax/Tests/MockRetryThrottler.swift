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

final class MockThrottler: RetryThrottler, Sendable {
  struct State: Sendable {
    var shouldThrottle: [Bool]
    var onRetryFailureCalled: [RetryResult] = []
    var onSuccessCalled = 0
    var throttleIndex = 0
  }

  private let state: Mutex<State>

  var onRetryFailureCalled: [RetryResult] {
    state.withLock { $0.onRetryFailureCalled }
  }

  var onSuccessCalled: Int {
    state.withLock { $0.onSuccessCalled }
  }

  init(shouldThrottle: [Bool] = []) {
    self.state = Mutex(State(shouldThrottle: shouldThrottle))
  }

  func throttleRetryAttempt() -> Bool {
    state.withLock {
      guard $0.throttleIndex < $0.shouldThrottle.count else { return false }
      let result = $0.shouldThrottle[$0.throttleIndex]
      $0.throttleIndex += 1
      return result
    }
  }

  func onRetryFailure(flow: RetryResult) {
    state.withLock {
      $0.onRetryFailureCalled.append(flow)
    }
  }

  func onSuccess() {
    state.withLock {
      $0.onSuccessCalled += 1
    }
  }
}
