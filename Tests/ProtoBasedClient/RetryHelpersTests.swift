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
import GoogleCloudTestHelpers
import GoogleGax
import Testing

@Suite struct RetryHelpersTests {
  // Verifies that `TestRetryPolicy` retries transient service errors—especially `INTERNAL`
  // (HTTP 500), which strict `AIP194` treats as permanent—both as a `RetryPolicy` and as a
  // `PollingErrorPolicy`.
  @Test func retriesTransientServiceErrors() {
    let policy = TestRetryPolicy()
    let retryState = RetryState(idempotent: false)
    let pollingState = PollingState()

    let internalError = RequestError.service(
      ServiceError(
        code: .internal,
        message: "An internal error has occurred",
        httpStatusCode: 500
      )
    )
    #expect(internalError.isTransientTestError)
    if case .retry = policy.onError(state: retryState, error: internalError) {
      // Expected
    } else {
      Issue.record("Expected TestRetryPolicy to retry INTERNAL (HTTP 500)")
    }
    if case .retry = policy.onError(state: pollingState, error: internalError) {
      // Expected
    } else {
      Issue.record("Expected TestRetryPolicy polling policy to retry INTERNAL (HTTP 500)")
    }

    for code: ServiceError in [
      ServiceError(code: .unavailable, message: "unavailable"),
      ServiceError(code: .resourceExhausted, message: "quota"),
      ServiceError(code: .deadlineExceeded, message: "timeout"),
      ServiceError(code: .unknown, message: "unknown"),
    ] {
      let err = RequestError.service(code)
      #expect(err.isTransientTestError)
      if case .retry = policy.onError(state: retryState, error: err) {
        // Expected
      } else {
        Issue.record("Expected TestRetryPolicy to retry \(code.code)")
      }
    }
  }

  @Test func rejectsPermanentErrors() {
    let policy = TestRetryPolicy()
    let retryState = RetryState(idempotent: true)
    let pollingState = PollingState()

    for code: ServiceError in [
      ServiceError(code: .notFound, message: "not found", httpStatusCode: 404),
      ServiceError(code: .alreadyExists, message: "exists", httpStatusCode: 409),
      ServiceError(code: .invalidArgument, message: "invalid", httpStatusCode: 400),
      ServiceError(code: .permissionDenied, message: "denied", httpStatusCode: 403),
    ] {
      let err = RequestError.service(code)
      #expect(!err.isTransientTestError)
      if case .permanent = policy.onError(state: retryState, error: err) {
        // Expected
      } else {
        Issue.record("Expected TestRetryPolicy to treat \(code.code) as permanent")
      }
      if case .permanent = policy.onError(state: pollingState, error: err) {
        // Expected
      } else {
        Issue.record("Expected TestRetryPolicy polling policy to treat \(code.code) as permanent")
      }
    }
  }

  @Test func testOptionsConfiguration() {
    #expect(testRetryOptions.idempotent == true)
    #expect(testRetryOptions.attemptTimeout == .seconds(15))
    #expect(testRetryOptions.retryPolicy != nil)
    #expect(testRetryOptions.pollingErrorPolicy != nil)
    #expect(testClientOptions.attemptTimeout == .seconds(15))
    #expect(testClientOptions.retryPolicy != nil)
  }
}
