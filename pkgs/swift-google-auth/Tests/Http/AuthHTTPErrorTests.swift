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

  // MARK: - String Formatting

  @Test func unsuccessfulResponseStringFormattingEmptyBody() {
    let response = HTTPClientResponse(
      version: .http2,
      status: .forbidden,
      headers: .init([
        ("X-Custom-Header", "CustomValue"),
        ("Set-Cookie", "SID=super-secret-cookie; HttpOnly"),
        ("Authorization", "Bearer echoed-auth-secret"),
      ]),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response)
    let anyError: any Error = error

    #expect(error.description == "HTTP status 403")
    #expect(String(describing: anyError) == "HTTP status 403")
    #expect(error.debugDescription == "AuthHTTPError.unsuccessfulResponse(statusCode: 403)")
    #expect(String(reflecting: anyError) == error.debugDescription)
    #expect(!error.debugDescription.contains("headers"))
    #expect(!error.debugDescription.contains("CustomValue"))
    #expect(!error.debugDescription.contains("super-secret-cookie"))
    #expect(!error.debugDescription.contains("echoed-auth-secret"))
  }

  @Test func unsuccessfulResponseStringFormattingOAuthJSON() {
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

    #expect(
      error.description == "HTTP status 400 (invalid_grant): Token has been expired or revoked.")
    #expect(String(describing: anyError) == error.description)
    #expect(
      error.debugDescription
        == #"AuthHTTPError.unsuccessfulResponse(statusCode: 400, error: "invalid_grant", message: "Token has been expired or revoked.")"#
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
    #expect(!error.description.contains("bytes"))
    #expect(!error.debugDescription.contains("bytes"))
    #expect(!error.debugDescription.contains("Content-Type"))

    // OAuth JSON with `error` code only (no `error_description`).
    let codeOnlyData = Data(#"{"error":"invalid_client"}"#.utf8)
    let codeOnlyError = AuthHTTPError.unsuccessfulResponse(
      response: HTTPClientResponse(version: .http2, status: .unauthorized),
      data: codeOnlyData
    )
    #expect(codeOnlyError.description == "HTTP status 401 (invalid_client)")
    #expect(
      codeOnlyError.debugDescription
        == #"AuthHTTPError.unsuccessfulResponse(statusCode: 401, error: "invalid_client")"#
    )
  }

  @Test func unsuccessfulResponseStringFormattingGoogleRPCJSON() {
    let expectedMessage = "Permission 'iam.serviceAccounts.getAccessToken' denied on resource."
    let rpcErrorJSON =
      #"{"error":{"code":403,"status":"PERMISSION_DENIED","message":"\#(expectedMessage)"}}"#
    let bodyData = Data(rpcErrorJSON.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .forbidden,
      headers: .init([("Content-Type", "application/json")]),
      body: .bytes(.init(data: bodyData)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)

    #expect(
      error.description == "HTTP status 403 (PERMISSION_DENIED): \(expectedMessage)"
    )
    #expect(
      error.debugDescription
        == "AuthHTTPError.unsuccessfulResponse(statusCode: 403, error: \"PERMISSION_DENIED\", message: \(String(reflecting: expectedMessage)))"
    )

    // Google RPC envelope with `message` only (no `status` string).
    let messageOnlyData = Data(#"{"error":{"code":400,"message":"Invalid argument"}}"#.utf8)
    let messageOnlyError = AuthHTTPError.unsuccessfulResponse(
      response: HTTPClientResponse(version: .http2, status: .badRequest),
      data: messageOnlyData
    )
    #expect(messageOnlyError.description == "HTTP status 400: Invalid argument")
    #expect(
      messageOnlyError.debugDescription
        == #"AuthHTTPError.unsuccessfulResponse(statusCode: 400, message: "Invalid argument")"#
    )
  }

  @Test func unsuccessfulResponseOmitsEchoedJSONCredentialsAndHeaders() {
    // Structured JSON error that also echoes sensitive credential fields alongside headers:
    // only allowlisted `error` and `error_description` fields may appear.
    let fakeAccessToken = "ya29" + ".a0FakeAccessTokenForTesting"
    let fakeRefreshToken = "1//" + "0gFakeRefreshTokenForTesting"
    let echoedJSON =
      #"{"error":"invalid_request","error_description":"Missing required parameter","refresh_token":""#
      + fakeRefreshToken
      + #"","client_secret":"my-top-secret-client-secret","subject_token":"raw-oidc-subject-secret","access_token":""#
      + fakeAccessToken + #""}"#
    let echoedData = Data(echoedJSON.utf8)
    let echoedResponse = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      headers: .init([
        ("Set-Cookie", "SID=session-cookie-secret"),
        ("Authorization", "Bearer header-bearer-secret"),
      ]),
      body: .bytes(.init(data: echoedData)),
    )
    let echoedError = AuthHTTPError.unsuccessfulResponse(response: echoedResponse, data: echoedData)

    #expect(
      echoedError.description == "HTTP status 400 (invalid_request): Missing required parameter")
    #expect(
      echoedError.debugDescription
        == #"AuthHTTPError.unsuccessfulResponse(statusCode: 400, error: "invalid_request", message: "Missing required parameter")"#
    )
    for formatted in [echoedError.description, echoedError.debugDescription] {
      #expect(!formatted.contains("refresh_token"))
      #expect(!formatted.contains("0gFakeRefreshTokenForTesting"))
      #expect(!formatted.contains("my-top-secret-client-secret"))
      #expect(!formatted.contains("raw-oidc-subject-secret"))
      #expect(!formatted.contains("a0FakeAccessTokenForTesting"))
      #expect(!formatted.contains("session-cookie-secret"))
      #expect(!formatted.contains("header-bearer-secret"))
    }
  }

  @Test(arguments: [
    Data("<html><body>Proxy error echoing subject_token=secret-123</body></html>".utf8),
    Data("grant_type=token-exchange&client_secret=form-secret-456".utf8),
    Data(#"{"unexpected_field":"unrecognized-json-secret-789"}"#.utf8),
    Data([0xFF, 0xFE, 0xFD]),
    Data(
      #"{"error":"invalid_request","error_description":"\#(String(repeating: "x", count: AuthHTTPError.maxStructuredErrorPayloadBytes))"}"#
        .utf8),
  ])
  func unsuccessfulResponseOmitsNonStandardPayloads(payload: Data) {
    let response = HTTPClientResponse(
      version: .http2,
      status: .badGateway,
      body: .bytes(.init(data: payload)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: payload)
    #expect(error.description == "HTTP status 502")
    #expect(error.debugDescription == "AuthHTTPError.unsuccessfulResponse(statusCode: 502)")
  }

  @Test func unsuccessfulResponseTruncatesLongStructuredErrorMessageCleanly() {
    // 1022 ASCII bytes followed by a 4-byte emoji (total 1026 UTF-8 bytes > 1024-byte cap).
    // Truncation must stop at byte 1022 rather than splitting the 4-byte scalar into U+FFFD.
    let asciiPrefix = String(repeating: "a", count: AuthHTTPError.maxErrorMessageBytes - 2)
    let json = #"{"error":"invalid_grant","error_description":"\#(asciiPrefix)🔒trailing"}"#
    let bodyData = Data(json.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      body: .bytes(.init(data: bodyData)),
    )
    let error = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)

    #expect(error.description == "HTTP status 400 (invalid_grant): \(asciiPrefix)")
    #expect(!error.description.contains("🔒"))
    #expect(!error.description.contains("trailing"))
    #expect(!error.description.contains("\u{FFFD}"))
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

    // Match the `any Error & Sendable` existential stored by `.decodingError` and `.unknown` so
    // Darwin `NSError` bridging formats `URLError` identically on macOS and Linux.
    struct SampleDecodeError: Error, Sendable, CustomStringConvertible {
      var description: String { "missing access_token" }
    }
    let sampleDecodeError: any Error & Sendable = SampleDecodeError()
    let decodingError = AuthHTTPError.decodingError(error: sampleDecodeError)
    #expect(decodingError.description == "Response decoding error: missing access_token")
    #expect(
      decodingError.debugDescription
        == "AuthHTTPError.decodingError(\(String(reflecting: sampleDecodeError)))"
    )
    #expect(String(reflecting: decodingError as any Error) == decodingError.debugDescription)

    let unknownUnderlying: any Error & Sendable = URLError(.unknown)
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

  @Test func credentialsErrorSurfacesStructuredAuthError() {
    let stsErrorJSON =
      #"{"error":"invalid_target","error_description":"The target service indicated by the \"audience\" parameters is invalid."}"#
    let bodyData = Data(stsErrorJSON.utf8)
    let response = HTTPClientResponse(
      version: .http2,
      status: .badRequest,
      headers: .init([
        ("Content-Type", "application/json"),
        ("Set-Cookie", "SID=secret-cookie"),
      ]),
      body: .bytes(.init(data: bodyData)),
    )
    let underlying = AuthHTTPError.unsuccessfulResponse(response: response, data: bodyData)
    let credentialsError: any Error = CredentialsError.cannotFetchToken(
      message: "STS token exchange failed",
      underlyingError: underlying
    )

    let described = String(describing: credentialsError)
    let reflected = String(reflecting: credentialsError)

    #expect(
      described
        == #"STS token exchange failed: HTTP status 400 (invalid_target): The target service indicated by the "audience" parameters is invalid."#
    )
    #expect(!described.contains("bytes"))
    #expect(!described.contains("secret-cookie"))
    #expect(reflected.contains("CredentialsError.cannotFetchToken: STS token exchange failed"))
    #expect(reflected.contains("statusCode: 400"))
    #expect(reflected.contains("invalid_target"))
    #expect(!reflected.contains("bytes"))
    #expect(!reflected.contains("secret-cookie"))
  }
}
