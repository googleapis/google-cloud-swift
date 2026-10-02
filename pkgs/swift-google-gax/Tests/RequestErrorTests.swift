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
    let localized = error as LocalizedError
    #expect(localized.errorDescription == error.description)
    #expect(localized.failureReason == "The request could not be mapped to a valid URL path.")
    #expect(
      localized.recoverySuggestion
        == "Verify that all required fields in the request (such as 'name' or 'parent') are set and correctly formatted."
    )
    #expect(error.localizedDescription == error.description)
  }

  @Test func requestErrorIOCase() {
    struct CustomIOError: Error, CustomStringConvertible {
      var description: String { "connection reset by peer" }
    }
    let ioErr = CustomIOError()
    let error: RequestError = .io(ioErr)

    #expect(error.description == "I/O error: connection reset by peer")
    #expect(error.debugDescription.hasPrefix("RequestError.io("))
    let localized = error as LocalizedError
    #expect(localized.errorDescription == error.description)
    #expect(localized.failureReason?.contains("connection reset by peer") == true)
    #expect(
      localized.recoverySuggestion
        == "Check network connectivity and retry the request if the operation is idempotent."
    )
    #expect(error.localizedDescription == error.description)
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
    let localized = error as LocalizedError
    #expect(localized.errorDescription == "HTTP error 503")
    #expect(localized.failureReason == "The server responded with HTTP status code 503.")
    #expect(
      localized.recoverySuggestion
        == "Review network settings and request parameters. Examine response headers or payload for details."
    )
    #expect(error.localizedDescription == "HTTP error 503")
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
    let localized = error as LocalizedError
    #expect(localized.errorDescription == error.description)
    #expect(
      localized.failureReason
        == "The service returned error code PERMISSION_DENIED: Access denied"
    )
    #expect(
      localized.recoverySuggestion
        == "Review the error code and details, and consult the service documentation."
    )
    #expect(error.localizedDescription == error.description)
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
    let localized = error as LocalizedError
    #expect(localized.errorDescription == error.description)
    #expect(
      localized.failureReason
        == "The retry or polling policy exceeded its elapsed time limit of 30.0 seconds."
    )
    #expect(
      localized.recoverySuggestion
        == "Increase the retry or polling policy limit (such as timeout duration or maximum attempt count)."
    )
  }

  @Test func requestErrorUnimplementedCase() {
    let error: RequestError = .unimplemented

    #expect(error.description == "Method unimplemented")
    #expect(error.debugDescription == "RequestError.unimplemented")
    let localized = error as LocalizedError
    #expect(localized.errorDescription == "Method unimplemented")
    #expect(localized.failureReason == "The requested method is not implemented.")
    #expect(
      localized.recoverySuggestion
        == "If using a mock client, implement the method. Otherwise, check for client library updates."
    )
  }

  @Test func requestErrorMalformedResponseCase() {
    let error: RequestError = .malformedResponse("missing 'name' field")

    #expect(error.description == "Malformed response: missing 'name' field")
    #expect(error.debugDescription.contains("RequestError.malformedResponse("))
    #expect(error.debugDescription.contains("missing 'name' field"))
    let localized = error as LocalizedError
    #expect(localized.errorDescription == "Malformed response: missing 'name' field")
    #expect(
      localized.failureReason == "The service returned a malformed response: missing 'name' field"
    )
    #expect(localized.recoverySuggestion == "Report this issue to the service team.")
  }

  @Test func requestErrorBadURLCase() {
    let error: RequestError = .badURL("ht tp://bad url")

    #expect(error.description == "Invalid endpoint URL: ht tp://bad url")
    #expect(error.debugDescription == "RequestError.badURL(\"ht tp://bad url\")")
    let localized = error as LocalizedError
    #expect(localized.errorDescription == "Invalid endpoint URL: ht tp://bad url")
    #expect(localized.failureReason == "The endpoint URL is invalid: ht tp://bad url")
    #expect(
      localized.recoverySuggestion
        == "Review and correct the endpoint URL configured for the client."
    )
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
    let timeLocalized = timeExhaustedWithoutSource as LocalizedError
    #expect(timeLocalized.errorDescription == timeExhaustedWithoutSource.description)
    #expect(
      timeLocalized.failureReason
        == "The retry or polling policy exceeded its elapsed time limit of 10.0 seconds."
    )
    #expect(
      timeLocalized.recoverySuggestion
        == "Increase the retry or polling policy limit (such as timeout duration or maximum attempt count)."
    )

    let attemptExhausted = PolicyExhaustedError.attemptCount(maximumAttempts: 5)
    #expect(
      attemptExhausted.description == "policy exhausted: attempt count limit of 5 exceeded"
    )
    #expect(
      attemptExhausted.debugDescription == "PolicyExhaustedError.attemptCount(maximumAttempts: 5)"
    )
    let attemptLocalized = attemptExhausted as LocalizedError
    #expect(attemptLocalized.errorDescription == attemptExhausted.description)
    #expect(
      attemptLocalized.failureReason
        == "The retry or polling policy exceeded its attempt limit of 5."
    )
    #expect(
      attemptLocalized.recoverySuggestion
        == "Increase the retry or polling policy limit (such as timeout duration or maximum attempt count)."
    )
  }
}
