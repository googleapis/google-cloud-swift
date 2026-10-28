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

import struct AsyncHTTPClient.HTTPClientResponse
import Foundation
import NIOFoundationCompat
import NIOHTTP1
import Testing

@testable import GoogleAuth

@Suite struct AuthHTTPErrorTest {
  private let testURL = URL(string: "https://example.com")!

  @Test func unsuccessfulResponseAccessors() {
    let bodyString = "Forbidden Access"
    let bodyData = Data(bodyString.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .forbidden,
      headers: .init([("X-Custom-Header", "CustomValue")]),
      body: .bytes(.init(data: bodyData)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)

    #expect(error.statusCode == 403)
    #expect(error.body == bodyString)
    #expect(error.bodyData == bodyData)
    #expect(error.headers?["X-Custom-Header"] == "CustomValue")
    #expect(error.urlError == nil)
  }

  @Test func unsuccessfulResponseInvalidUTF8Body() {
    let invalidUTF8Data = Data([0xFF, 0xFE, 0xFD])
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      body: .bytes(.init(data: invalidUTF8Data)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: invalidUTF8Data)

    #expect(error.statusCode == 400)
    #expect(error.body == nil)
    #expect(error.bodyData == invalidUTF8Data)
  }

  @Test func transportErrorAccessors() {
    let urlError = URLError(.timedOut)
    let error = AuthHTTPError.transportError(urlError)

    #expect(error.urlError == urlError)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }

  @Test func decodingErrorAccessors() {
    let decodingError = DecodingError.valueNotFound(
      String.self,
      DecodingError.Context(codingPath: [], debugDescription: "Test")
    )
    let error = AuthHTTPError.decodingError(error: decodingError)

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.headers == nil)
  }

  @Test func unknownErrorAccessors() {
    let genericError = URLError(.unknown)
    let error = AuthHTTPError.unknown(genericError)

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }

  @Test func invalidUTF8ResponseAccessors() {
    let error = AuthHTTPError.invalidUTF8Response

    #expect(error.urlError == nil)
    #expect(error.statusCode == nil)
    #expect(error.body == nil)
    #expect(error.bodyData == nil)
    #expect(error.headers == nil)
  }

  @Test(arguments: [
    (HTTPResponseStatus.internalServerError, true),
    (.notImplemented, true),
    (.badGateway, true),
    (.serviceUnavailable, true),
    (.gatewayTimeout, true),
    (.tooManyRequests, true),
    (.requestTimeout, true),
    (.badRequest, false),
    (.unauthorized, false),
    (.forbidden, false),
    (.notFound, false),
  ])
  func isRetryableStatusCodes(status: HTTPResponseStatus, expected: Bool) {
    let error = AuthHTTPError.unsuccessfulResponse(
      response: HTTPClientResponse(version: .http2, status: status)
    )
    #expect(error.isRetryable == expected)
    #expect(AuthHTTPError.isRetryable(error) == expected)

    let wrapped = CredentialsError.cannotFetchToken(message: "failed", underlyingError: error)
    #expect(AuthHTTPError.isRetryable(wrapped) == expected)
  }

  @Test func isRetryableErrorCases() {
    let decodingError = AuthHTTPError.decodingError(
      error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "corrupted"))
    )
    #expect(decodingError.isRetryable == false)
    #expect(AuthHTTPError.isRetryable(decodingError) == false)
    #expect(
      AuthHTTPError.isRetryable(
        CredentialsError.cannotFetchToken(message: "failed", underlyingError: decodingError)
      ) == false
    )

    let invalidUTF8 = AuthHTTPError.invalidUTF8Response
    #expect(invalidUTF8.isRetryable == false)
    #expect(AuthHTTPError.isRetryable(invalidUTF8) == false)
    #expect(
      AuthHTTPError.isRetryable(
        CredentialsError.cannotFetchToken(message: "failed", underlyingError: invalidUTF8)
      ) == false
    )

    let transportError = AuthHTTPError.transportError(URLError(.timedOut))
    #expect(transportError.isRetryable == true)
    #expect(AuthHTTPError.isRetryable(transportError) == true)
    #expect(
      AuthHTTPError.isRetryable(
        CredentialsError.cannotFetchToken(message: "failed", underlyingError: transportError)
      ) == true
    )

    let unknownError = AuthHTTPError.unknown(URLError(.unknown))
    #expect(unknownError.isRetryable == true)
    #expect(AuthHTTPError.isRetryable(unknownError) == true)
    #expect(
      AuthHTTPError.isRetryable(
        CredentialsError.cannotFetchToken(message: "failed", underlyingError: unknownError)
      ) == true
    )

    // Other CredentialsError cases are permanent
    #expect(
      AuthHTTPError.isRetryable(
        CredentialsError.cannotLoadFile(
          message: "missing", underlyingError: URLError(.fileDoesNotExist))
      ) == false
    )
    #expect(AuthHTTPError.isRetryable(CredentialsError.parseError("invalid")) == false)
    #expect(AuthHTTPError.isRetryable(CredentialsError.notSupported("unsupported")) == false)

    // Non-AuthHTTPError errors default to retryable
    #expect(AuthHTTPError.isRetryable(URLError(.cannotConnectToHost)) == true)
  }
}
