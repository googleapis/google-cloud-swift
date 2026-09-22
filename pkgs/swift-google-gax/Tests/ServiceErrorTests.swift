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
}
