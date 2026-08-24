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

@Suite struct StopOnConsecutiveErrorsTests {
  @Test func defaults() {
    let policy = StopOnConsecutiveErrors<Void>()
    #expect(policy.maxConsecutiveErrors == 3)
    #expect(policy.remainingTime(state: ResumeState()) == nil)
  }

  @Test func staticFactories() {
    let defaultPolicy: StopOnConsecutiveErrors<Void> = .stopOnConsecutiveErrors()
    #expect(defaultPolicy.maxConsecutiveErrors == 3)

    let customPolicy: StopOnConsecutiveErrors<Void> = .stopOnConsecutiveErrors(maxConsecutiveErrors: 5)
    #expect(customPolicy.maxConsecutiveErrors == 5)
  }

  @Test func recoverableVsPermanentErrors() {
    let policy = StopOnConsecutiveErrors<Void>(maxConsecutiveErrors: 2)
    let state = ResumeState()

    let transient503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    let transient408 = RequestError.http(HTTPDetails(http_status_code: 408, headers: [:]))
    let transient429 = RequestError.http(HTTPDetails(http_status_code: 429, headers: [:]))
    let transient502 = RequestError.http(HTTPDetails(http_status_code: 502, headers: [:]))
    let transient504 = RequestError.http(HTTPDetails(http_status_code: 504, headers: [:]))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))
    let permanent404 = RequestError.http(HTTPDetails(http_status_code: 404, headers: [:]))
    let permanent400 = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))
    let permanent401 = RequestError.http(HTTPDetails(http_status_code: 401, headers: [:]))
    let permanent403 = RequestError.http(HTTPDetails(http_status_code: 403, headers: [:]))
    let permanent412 = RequestError.http(HTTPDetails(http_status_code: 412, headers: [:]))
    let permanent499 = RequestError.http(HTTPDetails(http_status_code: 499, headers: [:]))
    let permanent500 = RequestError.http(HTTPDetails(http_status_code: 500, headers: [:]))

    // Permanent errors
    #expect(policy.onError(state: state, error: permanent404) == .permanent(permanent404))
    #expect(policy.onError(state: state, error: permanent400) == .permanent(permanent400))
    #expect(policy.onError(state: state, error: permanent401) == .permanent(permanent401))
    #expect(policy.onError(state: state, error: permanent403) == .permanent(permanent403))
    #expect(policy.onError(state: state, error: permanent412) == .permanent(permanent412))
    #expect(policy.onError(state: state, error: permanent499) == .permanent(permanent499))
    #expect(policy.onError(state: state, error: permanent500) == .permanent(permanent500))

    // Recoverable errors when below threshold
    state.consecutiveErrorCount = 1
    #expect(policy.onError(state: state, error: transient503) == .resume(transient503))
    #expect(policy.onError(state: state, error: transient408) == .resume(transient408))
    #expect(policy.onError(state: state, error: transient429) == .resume(transient429))
    #expect(policy.onError(state: state, error: transient502) == .resume(transient502))
    #expect(policy.onError(state: state, error: transient504) == .resume(transient504))
    #expect(policy.onError(state: state, error: ioError) == .resume(ioError))

    // Reaching consecutive threshold exhausts
    state.consecutiveErrorCount = 2
    #expect(policy.onError(state: state, error: transient503) == .exhausted(transient503))
  }
}
