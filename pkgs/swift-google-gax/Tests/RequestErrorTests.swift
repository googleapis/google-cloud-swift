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

@Suite struct RequestErrorTests {
  @Test func httpDetailsConformances() {
    let emptyDetails = HTTPDetails(statusCode: 404)
    #expect(emptyDetails.description == "HTTP status 404")
    #expect(emptyDetails.debugDescription.contains("statusCode: 404"))
    #expect(emptyDetails.debugDescription.contains("headers:"))

    let headers = HTTPHeaders([("content-type", "application/json")])
    let payload = Data("{\"error\": \"not found\"}".utf8)
    let details = HTTPDetails(statusCode: 404, headers: headers, payload: payload)
    #expect(details.description == "HTTP status 404")
    #expect(
      details.debugDescription.contains("statusCode: 404")
    )
    #expect(
      details.debugDescription.contains("payload: \"{\\\"error\\\": \\\"not found\\\"}\"")
    )

    let identical = HTTPDetails(statusCode: 404, headers: headers, payload: payload)
    #expect(details == identical)
    let different = HTTPDetails(statusCode: 500, headers: headers, payload: payload)
    #expect(details != different)
  }

  @Test func requestErrorBindingCase() {
    let bindingError = BindingError(paths: [
      PathMismatch(substitutions: [
        SubstitutionMismatch(fieldName: "name", problem: .unset)
      ])
    ])
    let error: RequestError = .binding(bindingError)

    #expect(error.description == "URL binding error: field 'name' needs to be set")
    #expect(error.debugDescription.hasPrefix("RequestError.binding(BindingError(paths:"))
  }

  @Test func requestErrorIOCase() {
    struct CustomIOError: Error, CustomStringConvertible {
      var description: String { "connection reset by peer" }
    }
    let ioErr = CustomIOError()
    let error: RequestError = .io(ioErr)

    #expect(error.description == "I/O error: connection reset by peer")
    #expect(error.debugDescription.hasPrefix("RequestError.io("))
  }

  @Test func requestErrorHTTPCase() {
    let details = HTTPDetails(
      statusCode: 503,
      headers: HTTPHeaders([("x-goog-test", "val")]),
      payload: Data("Service Unavailable".utf8)
    )
    let error: RequestError = .http(details)

    #expect(error.description == "HTTP error 503")
    #expect(error.debugDescription.contains("RequestError.http(HTTPDetails(statusCode: 503"))
  }

  @Test func requestErrorServiceCase() {
    let serviceError = ServiceError(
      code: .permissionDenied,
      message: "Access denied",
      httpStatusCode: 403
    )
    let error: RequestError = .service(serviceError)

    #expect(error.description == "PERMISSION_DENIED (HTTP 403): Access denied")
    #expect(error.debugDescription.hasPrefix("RequestError.service(ServiceError("))
  }

  @Test func requestErrorExhaustedCase() {
    let exhausted = PolicyExhaustedError.elapsedTime(
      maximumDuration: .seconds(30),
      source: .badURL("http://example.com")
    )
    let error: RequestError = .exhausted(exhausted)

    #expect(
      error.description
        == "policy exhausted: elapsed time limit of 30.0 seconds exceeded; last error: Invalid endpoint URL: http://example.com"
    )
    #expect(error.debugDescription.hasPrefix("RequestError.exhausted(PolicyExhaustedError."))
  }

  @Test func requestErrorUnimplementedCase() {
    let error: RequestError = .unimplemented

    #expect(error.description == "Method unimplemented")
    #expect(error.debugDescription == "RequestError.unimplemented")
  }

  @Test func requestErrorMalformedResponseCase() {
    let error: RequestError = .malformedResponse("missing 'name' field")

    #expect(error.description == "Malformed response: missing 'name' field")
    #expect(error.debugDescription.contains("RequestError.malformedResponse("))
    #expect(error.debugDescription.contains("missing 'name' field"))
  }

  @Test func requestErrorBadURLCase() {
    let error: RequestError = .badURL("ht tp://bad url")

    #expect(error.description == "Invalid endpoint URL: ht tp://bad url")
    #expect(error.debugDescription == "RequestError.badURL(\"ht tp://bad url\")")
  }

  @Test func policyExhaustedErrorConformances() {
    let timeExhaustedWithoutSource = PolicyExhaustedError.elapsedTime(maximumDuration: .seconds(10))
    #expect(
      timeExhaustedWithoutSource.description
        == "policy exhausted: elapsed time limit of 10.0 seconds exceeded"
    )
    #expect(
      timeExhaustedWithoutSource.debugDescription
        == "PolicyExhaustedError.elapsedTime(maximumDuration: 10.0 seconds)"
    )

    let timeExhaustedWithSource = PolicyExhaustedError.elapsedTime(
      maximumDuration: .seconds(10), source: .unimplemented)
    #expect(
      timeExhaustedWithSource.debugDescription
        == "PolicyExhaustedError.elapsedTime("
        + "maximumDuration: 10.0 seconds, source: RequestError.unimplemented)"
    )

    let timeExhaustedNoLimit = PolicyExhaustedError.elapsedTime(source: .unimplemented)
    #expect(
      timeExhaustedNoLimit.debugDescription
        == "PolicyExhaustedError.elapsedTime(source: RequestError.unimplemented)"
    )

    let timeExhaustedEmpty = PolicyExhaustedError.elapsedTime()
    #expect(
      timeExhaustedEmpty.debugDescription
        == "PolicyExhaustedError.elapsedTime()"
    )

    let attemptExhausted = PolicyExhaustedError.attemptCount(maximumAttempts: 5)
    #expect(
      attemptExhausted.description == "policy exhausted: attempt count limit of 5 exceeded"
    )
    #expect(
      attemptExhausted.debugDescription == "PolicyExhaustedError.attemptCount(maximumAttempts: 5)"
    )

    let attemptExhaustedWithSource = PolicyExhaustedError.attemptCount(
      maximumAttempts: 5, source: .unimplemented)
    #expect(
      attemptExhaustedWithSource.debugDescription
        == "PolicyExhaustedError.attemptCount(maximumAttempts: 5, source: RequestError.unimplemented)"
    )
  }
}
