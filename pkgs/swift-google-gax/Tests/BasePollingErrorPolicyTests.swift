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
import GoogleGax
import GoogleRpc
import Testing

@Suite struct BasePollingErrorPolicyTests {
  @Test("Verify BasePollingErrorPolicy.unbounded() continues on transient errors")
  func unboundedContinuesOnTransient() throws {
    let p = BasePollingErrorPolicy.unbounded()
    let state = PollingState().with {
      $0.attemptCount = 100
    }
    let unavailable = RequestError.service(
      ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))
    let resourceExhausted = RequestError.service(
      ServiceError(code: GoogleRpc.Code.resourceExhausted, message: "RESOURCE_EXHAUSTED"))
    let permissionDenied = RequestError.service(
      ServiceError(code: GoogleRpc.Code.permissionDenied, message: "PERMISSION_DENIED"))

    #expect(p.onError(state: state, error: unavailable) == .retry(unavailable))
    #expect(p.onError(state: state, error: resourceExhausted) == .retry(resourceExhausted))
    #expect(p.onError(state: state, error: permissionDenied) == .permanent(permissionDenied))
    try p.onInProgress(state: state)
  }

  @Test("Verify BasePollingErrorPolicy.defaultPolicy enforces 30-minute limit")
  func defaultPolicyBounds() throws {
    let p = BasePollingErrorPolicy.defaultPolicy
    let start = ContinuousClock.now
    let unavailable = RequestError.service(
      ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))

    let activeState = PollingState().with {
      $0.start = start
      $0.attemptCount = 1
    }
    #expect(p.onError(state: activeState, error: unavailable) == .retry(unavailable))
    try p.onInProgress(state: activeState)

    let expiredState = PollingState().with {
      $0.start = start - .seconds(30 * 60 + 1)
      $0.attemptCount = 1
    }
    #expect(p.onError(state: expiredState, error: unavailable) == .exhausted(unavailable))
  }
}
