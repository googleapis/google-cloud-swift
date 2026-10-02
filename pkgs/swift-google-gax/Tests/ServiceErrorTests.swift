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
@_spi(GoogleCloudInternal) import GoogleGax
import GoogleRpc
import Testing

@Suite struct ServiceErrorTests {
  @Test func unifiedInitializerDefaults() {
    let error = ServiceError(code: .notFound, message: "Resource not found")
    #expect(error.code == .notFound)
    #expect(error.message == "Resource not found")
    #expect(error.details.isEmpty)
    #expect(error.httpStatusCode == nil)

    let withHttp = ServiceError(
      code: .notFound,
      message: "Resource not found",
      httpStatusCode: 404
    )
    #expect(withHttp.code == .notFound)
    #expect(withHttp.message == "Resource not found")
    #expect(withHttp.details.isEmpty)
    #expect(withHttp.httpStatusCode == 404)
  }

  @Test func errorConformanceAllowsDirectThrowing() throws {
    let expected = ServiceError(code: .notFound, message: "missing item")
    #expect(throws: expected) {
      throw ServiceError(code: .notFound, message: "missing item")
    }
  }

  @Test func equatableConformance() {
    let expected = ServiceError(code: .permissionDenied, message: "denied")
    let actual = ServiceError(code: .permissionDenied, message: "denied")
    #expect(actual == expected)

    let caught: RequestError = .service(actual)
    #expect(caught == .service(expected))

    let differentCode = ServiceError(code: .unauthenticated, message: "denied")
    #expect(expected != differentCode)

    let differentHttp = ServiceError(
      code: .permissionDenied,
      message: "denied",
      httpStatusCode: 403
    )
    #expect(expected != differentHttp)
  }

  @Test func customStringConvertibleFormatting() {
    let basic = ServiceError(code: .notFound, message: "Bucket does not exist")
    #expect(basic.description == "NOT_FOUND: Bucket does not exist")

    let withHttp = ServiceError(
      code: .invalidArgument,
      message: "Invalid field 'name'",
      httpStatusCode: 400
    )
    #expect(withHttp.description == "INVALID_ARGUMENT (HTTP 400): Invalid field 'name'")

    let detail = StatusDetail.errorInfo(
      GoogleRpc.ErrorInfo().with {
        $0.reason = "QUOTA_EXCEEDED"
        $0.domain = "googleapis.com"
      })
    let withDetails = ServiceError(
      code: .resourceExhausted,
      message: "Quota exceeded",
      details: [detail],
      httpStatusCode: 429
    )
    #expect(withDetails.description.hasPrefix("RESOURCE_EXHAUSTED (HTTP 429): Quota exceeded ["))
  }

  @Test func debugDescriptionAndLocalizedError() {
    let error = ServiceError(
      code: .notFound,
      message: "Resource missing",
      httpStatusCode: 404
    )
    #expect(
      error.debugDescription
        == "ServiceError(code: notFound, httpStatusCode: 404, message: \"Resource missing\")"
    )
    let localized = error as LocalizedError
    #expect(localized.errorDescription == error.description)
    #expect(localized.failureReason == "Resource missing")
    #expect(
      localized.recoverySuggestion
        == "Review the error code and details, and consult the service documentation."
    )
    #expect(error.localizedDescription == error.description)
  }

  @Test func googleRpcCodeFromHttpStatusCode() {
    let mappings: [(Int, GoogleRpc.Code)] = [
      (200, .ok),
      (204, .ok),
      (400, .invalidArgument),
      (401, .unauthenticated),
      (403, .permissionDenied),
      (404, .notFound),
      (409, .alreadyExists),
      (412, .failedPrecondition),
      (429, .resourceExhausted),
      (499, .cancelled),
      (500, .internal),
      (501, .unimplemented),
      (503, .unavailable),
      (504, .deadlineExceeded),
      (418, .unknown),
      (999, .unknown),
    ]
    for (status, expectedCode) in mappings {
      #expect(GoogleRpc.Code(httpStatusCode: status) == expectedCode)
    }
  }

  @Test func googleRpcCodeToHttpStatusCode() {
    let mappings: [(GoogleRpc.Code, Int)] = [
      (.ok, 200),
      (.cancelled, 499),
      (.unknown, 500),
      (.invalidArgument, 400),
      (.deadlineExceeded, 504),
      (.notFound, 404),
      (.alreadyExists, 409),
      (.permissionDenied, 403),
      (.resourceExhausted, 429),
      (.failedPrecondition, 412),
      (.aborted, 409),
      (.outOfRange, 400),
      (.unimplemented, 501),
      (.internal, 500),
      (.unavailable, 503),
      (.dataLoss, 500),
      (.unauthenticated, 401),
    ]
    for (code, expectedStatus) in mappings {
      #expect(code.httpStatusCode == expectedStatus)
    }
  }
}
