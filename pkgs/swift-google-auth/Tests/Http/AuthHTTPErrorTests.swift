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

  @Test func unsuccessfulResponseStringFormattingEmptyBody() {
    let response = HTTPClientResponse(
      version: .http2,
      status: .forbidden,
      headers: .init([("X-Custom-Header", "CustomValue")]),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response)
    let anyError: any Error = error

    #expect(error.description == "HTTP status 403")
    #expect(String(describing: anyError) == "HTTP status 403")
    #expect(
      error.debugDescription.hasPrefix(
        "AuthHTTPError.unsuccessfulResponse(statusCode: 403, headers:"))
    #expect(error.debugDescription.contains("X-Custom-Header"))
    #expect(!error.debugDescription.contains("body:"))
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func unsuccessfulResponseStringFormattingWithJSONBody() {
    let oauthErrorJSON =
      #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#
    let bodyData = Data(oauthErrorJSON.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      headers: .init([("Content-Type", "application/json")]),
      body: .bytes(.init(data: bodyData)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)
    let anyError: any Error = error

    #expect(error.description == "HTTP status 400: \(oauthErrorJSON)")
    #expect(String(describing: anyError) == error.description)
    #expect(error.debugDescription.contains("statusCode: 400"))
    #expect(error.debugDescription.contains("Content-Type"))
    #expect(error.debugDescription.contains("body: \(String(reflecting: oauthErrorJSON))"))
    #expect(!error.description.contains("bytes"))
    #expect(!error.debugDescription.contains("bytes"))
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func unsuccessfulResponseStringFormattingTruncatesLargeBody() {
    let prefixPart = String(repeating: "a", count: AuthHTTPError.maxBodyPreviewBytes)
    let suffixPart = "SHOULD_BE_TRUNCATED"
    let bodyData = Data((prefixPart + suffixPart).utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .internalServerError,
      body: .bytes(.init(data: bodyData)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)

    #expect(error.description == "HTTP status 500: \(prefixPart)")
    #expect(!error.description.contains(suffixPart))
    #expect(error.debugDescription.contains("body: \(String(reflecting: prefixPart))"))
    #expect(!error.debugDescription.contains(suffixPart))
  }

  @Test func unsuccessfulResponseStringFormattingInvalidUTF8Body() {
    let invalidUTF8Data = Data([0xFF, 0xFE, 0xFD])
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      body: .bytes(.init(data: invalidUTF8Data)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: invalidUTF8Data)

    #expect(error.description.hasPrefix("HTTP status 400: "))
    #expect(error.description.contains("\u{FFFD}"))
    #expect(!error.description.contains("bytes"))
    #expect(error.debugDescription.contains("\u{FFFD}"))
    #expect(!error.debugDescription.contains("bytes"))
  }

  @Test func otherCasesStringFormatting() {
    let urlError = URLError(.timedOut)
    let transportError = AuthHTTPError.transportError(urlError)
    #expect(transportError.description == "Transport error: \(urlError)")
    #expect(
      transportError.debugDescription
        == "AuthHTTPError.transportError(\(String(reflecting: urlError)))"
    )
    #expect(String(reflecting: transportError as any Error) == transportError.debugDescription)

    struct SampleDecodeError: Error, Sendable, CustomStringConvertible {
      var description: String { "missing access_token" }
    }
    let sampleDecodeError = SampleDecodeError()
    let decodingError = AuthHTTPError.decodingError(error: sampleDecodeError)
    #expect(decodingError.description == "Response decoding error: missing access_token")
    #expect(
      decodingError.debugDescription
        == "AuthHTTPError.decodingError(\(String(reflecting: sampleDecodeError)))"
    )
    #expect(String(reflecting: decodingError as any Error) == decodingError.debugDescription)

    let unknownUnderlying = URLError(.unknown)
    let unknownError = AuthHTTPError.unknown(unknownUnderlying)
    #expect(unknownError.description == "Unexpected HTTP error: \(unknownUnderlying)")
    #expect(
      unknownError.debugDescription
        == "AuthHTTPError.unknown(\(String(reflecting: unknownUnderlying)))"
    )
    #expect(String(reflecting: unknownError as any Error) == unknownError.debugDescription)

    let invalidUTF8 = AuthHTTPError.invalidUTF8Response
    #expect(invalidUTF8.description == "Response body is not valid UTF-8")
    #expect(
      invalidUTF8.debugDescription
        == "AuthHTTPError.invalidUTF8Response: Response body is not valid UTF-8"
    )
    #expect(String(reflecting: invalidUTF8 as any Error) == invalidUTF8.debugDescription)
  }

  @Test func credentialsErrorSurfacesUnsuccessfulResponseBody() {
    let stsErrorJSON =
      #"{"error":"invalid_target","error_description":"The target service indicated by the \"audience\" parameters is invalid."}"#
    let bodyData = Data(stsErrorJSON.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      headers: .init([("Content-Type", "application/json")]),
      body: .bytes(.init(data: bodyData)),
    )
    let underlying = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)
    let credentialsError: any Error = CredentialsError.cannotFetchToken(
      message: "STS token exchange failed",
      underlyingError: underlying
    )

    let described = String(describing: credentialsError)
    let reflected = String(reflecting: credentialsError)

    #expect(described == "STS token exchange failed: HTTP status 400: \(stsErrorJSON)")
    #expect(!described.contains("bytes"))
    #expect(reflected.contains("CredentialsError.cannotFetchToken: STS token exchange failed"))
    #expect(reflected.contains("statusCode: 400"))
    #expect(reflected.contains("invalid_target"))
    #expect(!reflected.contains("bytes"))
  }
}
