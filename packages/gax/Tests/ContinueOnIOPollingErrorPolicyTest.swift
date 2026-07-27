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

@Suite struct RetryIOPollingErrorPolicyTests {
  @Test func continueIOOnError() {
    let mock = MockPollingPolicy(onError: { _, e in .permanent(e) })
    let policy = mock.continueOnIoErrors()

    let ioError = mockIOError()
    #expect(policy.onError(state: PollingState(), error: ioError) == .retry(ioError))

    let otherError = RequestError.binding("err")
    #expect(policy.onError(state: PollingState(), error: otherError) == .permanent(otherError))
  }

  @Test func continueIOOnInProgress() throws {
    let called = Mutex(false)
    let mock = MockPollingPolicy(onInProgress: { _, _ in
      called.withLock { $0 = true }
    })
    let policy = mock.continueOnIoErrors()

    try policy.onInProgress(state: PollingState(), name: "op-name")
    #expect(called.withLock { $0 })
  }
}
