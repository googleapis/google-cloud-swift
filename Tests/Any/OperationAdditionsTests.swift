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
import GoogleCloudSecretManagerV1
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) import GoogleLongRunning
import GoogleRpc
@_spi(GoogleCloudInternal) import GoogleWKT
import Testing

@Suite struct OperationAdditionsTests {
  @Test func extractStatusPreservesErrorDetails() throws {
    let errorInfo = GoogleRpc.ErrorInfo().with {
      $0.reason = "QUOTA_EXCEEDED"
      $0.domain = "googleapis.com"
      $0.metadata = ["consumer": "projects/123"]
    }
    let badRequest = GoogleRpc.BadRequest().with {
      $0.fieldViolations = [
        GoogleRpc.BadRequest.FieldViolation().with {
          $0.field = "secret_id"
          $0.description = "Invalid secret ID"
        }
      ]
    }
    let retryInfo = GoogleRpc.RetryInfo().with {
      $0.retryDelay = try? GoogleWKT.WKTDuration(seconds: 5, nanos: 0)
    }

    let status = try GoogleRpc.Status().with {
      $0.code = Int32(GoogleRpc.Code.resourceExhausted.intValue!)
      $0.message = "Quota exceeded for quota metric"
      $0.details = [
        try GoogleWKT.WKTAny(fromMessage: errorInfo),
        try GoogleWKT.WKTAny(fromMessage: badRequest),
        try GoogleWKT.WKTAny(fromMessage: retryInfo),
      ]
    }

    let operation = GoogleLongRunning.Operation().with {
      $0.done = true
      $0.result = .error(status)
    }

    let state = try operation._extractStatus(Secret.self)
    #expect(state.done)
    guard case .failure(let error) = state.result,
      let requestError = error as? GoogleGax.RequestError,
      case .service(let serviceError) = requestError
    else {
      Issue.record("Expected RequestError.service failure, got \(String(describing: state.result))")
      return
    }

    #expect(serviceError.code == .resourceExhausted)
    #expect(serviceError.message == "Quota exceeded for quota metric")
    #expect(
      serviceError.details == [
        .errorInfo(errorInfo),
        .badRequest(badRequest),
        .retryInfo(retryInfo),
      ]
    )
  }

  @Test func extractStatusEmptyPreservesErrorDetails() throws {
    let localizedMessage = GoogleRpc.LocalizedMessage().with {
      $0.locale = "en-US"
      $0.message = "The operation could not be completed."
    }
    let status = try GoogleRpc.Status().with {
      $0.code = Int32(GoogleRpc.Code.failedPrecondition.intValue!)
      $0.message = "Precondition check failed"
      $0.details = [
        try GoogleWKT.WKTAny(fromMessage: localizedMessage)
      ]
    }

    let operation = GoogleLongRunning.Operation().with {
      $0.done = true
      $0.result = .error(status)
    }

    let state = try operation._extractStatusEmpty()
    #expect(state.done)
    guard case .failure(let error) = state.result,
      let requestError = error as? GoogleGax.RequestError,
      case .service(let serviceError) = requestError
    else {
      Issue.record("Expected RequestError.service failure, got \(String(describing: state.result))")
      return
    }

    #expect(serviceError.code == .failedPrecondition)
    #expect(serviceError.message == "Precondition check failed")
    #expect(serviceError.details == [.localizedMessage(localizedMessage)])
  }
}
