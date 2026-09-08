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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import GoogleRpc
import Testing

@Suite struct StorageBaseRetryPolicyTests {
  private func isRetry(_ result: RetryResult) -> Bool {
    if case .retry = result { true } else { false }
  }

  private func isPermanent(_ result: RetryResult) -> Bool {
    if case .permanent = result { true } else { false }
  }

  private func isExhausted(_ result: RetryResult) -> Bool {
    if case .exhausted = result { true } else { false }
  }

  private func idempotentState() -> RetryState {
    RetryState(idempotent: true)
  }

  private func nonIdempotentState() -> RetryState {
    RetryState(idempotent: false)
  }

  @Test func storageRetryErrorsHTTPStatusCodes() {
    let policy = StorageRetryErrors()
    let state = idempotentState()

    // Retryable HTTP codes: 408, 429, and 500...599
    let retryableCodes = [408, 429, 500, 502, 503, 504, 599]
    for code in retryableCodes {
      let error = RequestError.http(HTTPDetails(http_status_code: code, headers: [:]))
      #expect(
        isRetry(policy.onError(state: state, error: error)), "Expected code \(code) to be retryable"
      )
    }

    // Non-retryable HTTP codes
    let nonRetryableCodes = [400, 401, 403, 404, 409, 412]
    for code in nonRetryableCodes {
      let error = RequestError.http(HTTPDetails(http_status_code: code, headers: [:]))
      #expect(
        isPermanent(policy.onError(state: state, error: error)),
        "Expected code \(code) to be permanent")
    }
  }

  @Test func storageRetryErrorsServiceCodes() {
    let policy = StorageRetryErrors()
    let state = idempotentState()

    // Retryable gRPC codes: unavailable, resourceExhausted, deadlineExceeded, internal
    let retryableCodes: [GoogleRpc.Code] = [
      .unavailable,
      .resourceExhausted,
      .deadlineExceeded,
      .`internal`,
    ]
    for code in retryableCodes {
      let error = RequestError.service(ServiceError(code: code, message: "transient"))
      #expect(
        isRetry(policy.onError(state: state, error: error)), "Expected code \(code) to be retryable"
      )
    }

    // Non-retryable gRPC codes
    let nonRetryableCodes: [GoogleRpc.Code] = [
      .ok,
      .cancelled,
      .unknown,
      .invalidArgument,
      .notFound,
      .alreadyExists,
      .permissionDenied,
      .failedPrecondition,
      .aborted,
      .outOfRange,
      .unimplemented,
      .dataLoss,
      .unauthenticated,
    ]
    for code in nonRetryableCodes {
      let error = RequestError.service(ServiceError(code: code, message: "permanent"))
      #expect(
        isPermanent(policy.onError(state: state, error: error)),
        "Expected code \(code) to be permanent")
    }
  }

  @Test func storageBaseRetryPolicyIdempotency() {
    let policy = StorageBaseRetryPolicy()

    let transientHttp = RequestError.http(HTTPDetails(http_status_code: 500, headers: [:]))
    let transientRpc = RequestError.service(
      ServiceError(code: Code.`internal`, message: "internal error"))
    let ioError = RequestError.io(NSError(domain: "test", code: -1))
    let permanentHttp = RequestError.http(HTTPDetails(http_status_code: 400, headers: [:]))

    // Idempotent: retries transient HTTP, transient RPC, and I/O
    #expect(isRetry(policy.onError(state: idempotentState(), error: transientHttp)))
    #expect(isRetry(policy.onError(state: idempotentState(), error: transientRpc)))
    #expect(isRetry(policy.onError(state: idempotentState(), error: ioError)))
    #expect(isPermanent(policy.onError(state: idempotentState(), error: permanentHttp)))

    // Non-idempotent: always permanent, even for transient errors
    #expect(isPermanent(policy.onError(state: nonIdempotentState(), error: transientHttp)))
    #expect(isPermanent(policy.onError(state: nonIdempotentState(), error: transientRpc)))
    #expect(isPermanent(policy.onError(state: nonIdempotentState(), error: ioError)))
  }

  @Test func storageBaseRetryPolicyDefaultPolicy() {
    let policy = StorageBaseRetryPolicy.defaultPolicy
    let state = idempotentState()

    let internalError = RequestError.service(
      ServiceError(code: Code.`internal`, message: "internal"))
    #expect(isRetry(policy.onError(state: state, error: internalError)))

    let unavailableError = RequestError.service(
      ServiceError(code: Code.unavailable, message: "unavailable"))
    #expect(isRetry(policy.onError(state: state, error: unavailableError)))

    let err503 = RequestError.http(HTTPDetails(http_status_code: 503, headers: [:]))
    #expect(isRetry(policy.onError(state: state, error: err503)))

    let err500 = RequestError.http(HTTPDetails(http_status_code: 500, headers: [:]))
    #expect(isRetry(policy.onError(state: state, error: err500)))

    let permanent = RequestError.http(HTTPDetails(http_status_code: 404, headers: [:]))
    #expect(isPermanent(policy.onError(state: state, error: permanent)))
  }
}
