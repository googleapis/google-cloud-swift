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

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix
import Synchronization
import Testing
@testable import GoogleAuth

@Suite struct AuthHTTPClientTest {
  @Test func clientPerformsGetAndDecodesSnakeCase() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-token-123", expiresIn: 3600)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .GET)
        #expect(request.headers["X-Goog-Custom-Header"] == ["HeaderValue"])
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let response: MockTokenResponse = try await client.get(
      url: targetURL,
      headers: ["X-Goog-Custom-Header": "HeaderValue"]
    )

    #expect(response == mockPayload)
  }

  @Test func clientPerformsPostAndDecodesSnakeCase() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-post-token", expiresIn: 1800)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/json"])

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let response: MockTokenResponse = try await client.post(
      url: targetURL,
      body: ["grant_type": "refresh_token"]
    )

    #expect(response == mockPayload)
  }

  @Test func clientPerformsPostEncodesBodyInSnakeCase() async throws {
    struct SampleRequestBody: Encodable {
      let grantType: String
      let clientId: String
      let clientSecret: String
      let refreshToken: String
    }

    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-post-token", expiresIn: 1800)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedResponse = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/json"])

        guard let buffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Missing request body")
          return HTTPClientResponse(status: .badRequest)
        }
        let bodyData = Data(buffer: buffer)
        guard let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
          Issue.record("Failed to deserialize request body JSON")
          return HTTPClientResponse(status: .badRequest)
        }

        // Verify snake_case field names per RFC 6749 Sections 6 & 2.3.1 and Google Identity:
        // https://datatracker.ietf.org/doc/html/rfc6749#section-6
        // https://datatracker.ietf.org/doc/html/rfc6749#section-2.3.1
        // https://developers.google.com/identity/protocols/oauth2/web-server#offline
        #expect(json["grant_type"] as? String == "refresh_token")
        #expect(json["client_id"] as? String == "test-client-id")
        #expect(json["client_secret"] as? String == "test-client-secret")
        #expect(json["refresh_token"] as? String == "test-refresh-token")
        #expect(json["grantType"] == nil)
        #expect(json["clientId"] == nil)
        #expect(json["clientSecret"] == nil)
        #expect(json["refreshToken"] == nil)

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedResponse)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let requestBody = SampleRequestBody(
      grantType: "refresh_token",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )
    let response: MockTokenResponse = try await client.post(
      url: targetURL,
      body: requestBody
    )
    #expect(response == mockPayload)
  }

  @Test func clientThrowsHTTPStatusCodeError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/invalid")!
    let errorPayload =
      #"{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}"#
    let errorData = Data(errorPayload.utf8)
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        return HTTPClientResponse(
          version: .http2,
          status: .serviceUnavailable,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: errorData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let error = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    #expect(error?.statusCode == 503)
    #expect(error?.body == errorPayload)
    #expect(error?.bodyData == errorData)
  }

  @Test func clientPopulatesErrorBodyAcrossMethods() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let errorPayload =
      #"{"error": "invalid_grant", "error_description": "Token has been expired or revoked."}"#
    let errorData = Data(errorPayload.utf8)
    let makeErrorResponse: MockHTTPClient.Closure = { _ in
      HTTPClientResponse(
        version: .http2,
        status: .badRequest,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: errorData)),
      )
    }

    let client = AuthHTTPClient(
      mock: MockHTTPClient([makeErrorResponse, makeErrorResponse, makeErrorResponse])
    )

    let getStringError = await #expect(throws: AuthHTTPError.self) {
      _ = try await client.getString(url: targetURL)
    }
    #expect(getStringError?.statusCode == 400)
    #expect(getStringError?.body == errorPayload)
    #expect(getStringError?.bodyData == errorData)

    let postError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.post(
        url: targetURL,
        body: ["grant_type": "refresh_token"]
      )
    }
    #expect(postError?.statusCode == 400)
    #expect(postError?.body == errorPayload)
    #expect(postError?.bodyData == errorData)

    let postDataError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.postData(
        url: targetURL,
        bodyData: Data("grant_type=refresh_token".utf8),
        contentType: "application/x-www-form-urlencoded"
      )
    }
    #expect(postDataError?.statusCode == 400)
    #expect(postDataError?.body == errorPayload)
    #expect(postDataError?.bodyData == errorData)
  }

  @Test func clientPerformsGetAndReturnsPlainTextString() async throws {
    let targetURL = URL(string: "http://metadata.google.internal/email")!
    let mockEmail = "test-service-account@google.com"
    let mockData = Data(mockEmail.utf8)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .GET)
        #expect(request.headers["Metadata-Flavor"] == ["Google"])

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          body: .bytes(.init(data: mockData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let result = try await client.getString(
      url: targetURL,
      headers: ["Metadata-Flavor": "Google"]
    )

    #expect(result == mockEmail)
  }

  @Test func clientThrowsNetworkError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        throw URLError(.notConnectedToInternet)
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
  }

  @Test func clientUsesDefaultInit() {
    let _ = AuthHTTPClient()
  }

  @Test func clientGetStringFailsOnInvalidUTF8() async throws {
    let targetURL = URL(string: "http://metadata.google.internal/invalid-utf8")!
    let mockData = Data([0xFF, 0xFE, 0xFD])  // Invalid UTF-8
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          body: .bytes(.init(data: mockData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    await #expect(throws: AuthHTTPError.self) {
      let s = try await client.getString(url: targetURL)
      print(" s = \(s)")
    }
  }

  @Test func clientPerformsPostWithCustomHeaders() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-post-token", expiresIn: 1800)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["X-Custom-Header"] == ["CustomValue"])

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let response: MockTokenResponse = try await client.post(
      url: targetURL,
      body: ["grant_type": "refresh_token"],
      headers: ["X-Custom-Header": "CustomValue"]
    )

    #expect(response == mockPayload)
  }

  @Test func clientThrowsOnEmptyHTTPResponse() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: Data())),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
  }

  @Test func clientPerformsPostDataAndDecodesSnakeCase() async throws {
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-sts-token-xyz", expiresIn: 3600)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let postBody = Data("grant_type=urn:ietf:params:oauth:grant-type:token-exchange".utf8)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/x-www-form-urlencoded"])
        #expect(request.headers["X-Custom-Header"] == ["Val"])
        let buffer = try await request.body!.collect(upTo: 1024 * 1024)
        let got = Data(buffer: buffer)
        #expect(got == postBody)

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let response: MockTokenResponse = try await client.postData(
      url: targetURL,
      bodyData: postBody,
      contentType: "application/x-www-form-urlencoded",
      headers: ["X-Custom-Header": "Val"]
    )

    #expect(response == mockPayload)
    #expect(mock.recordedTimeouts == [AuthHTTPClient.defaultTimeout])
  }

  @Test func clientForwardsTimeoutOverrideAcrossMethods() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-token", expiresIn: 3600)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedJSON = try encoder.encode(mockPayload)
    let plainTextData = Data("plain-text-response".utf8)

    let makeJSONResponse: MockHTTPClient.Closure = { _ in
      HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedJSON)),
      )
    }
    let makeStringResponse: MockHTTPClient.Closure = { _ in
      HTTPClientResponse(
        version: .http2,
        status: .ok,
        body: .bytes(.init(data: plainTextData)),
      )
    }

    let mock = MockHTTPClient([
      makeJSONResponse,
      makeJSONResponse,
      makeStringResponse,
      makeJSONResponse,
      makeJSONResponse,
    ])
    let client = AuthHTTPClient(mock: mock)

    let _: MockTokenResponse = try await client.get(url: targetURL)
    let _: MockTokenResponse = try await client.get(url: targetURL, timeout: .seconds(2))
    let _ = try await client.getString(url: targetURL, timeout: .seconds(3))
    let _: MockTokenResponse = try await client.post(
      url: targetURL,
      body: ["grant_type": "refresh_token"],
      timeout: .seconds(5)
    )
    let _: MockTokenResponse = try await client.postData(
      url: targetURL,
      bodyData: Data("grant_type=refresh_token".utf8),
      contentType: "application/x-www-form-urlencoded",
      timeout: .milliseconds(750)
    )

    #expect(
      mock.recordedTimeouts == [
        .seconds(30),
        .seconds(2),
        .seconds(3),
        .seconds(5),
        .milliseconds(750),
      ]
    )
  }

  @Test func clientPropagatesCancellationErrorUnwrapped() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mock = MockHTTPClient([
      { _ in
        throw CancellationError()
      }
    ])
    let client = AuthHTTPClient(mock: mock)

    await #expect(throws: CancellationError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
  }

  @Test func clientCancellingStalledBodyPropagatesCancellationError() async throws {
    let targetURL = URL(string: "http://metadata.google.internal/token")!
    let started = AsyncStream<Void>.makeStream()
    let mock = MockHTTPClient([
      { _ in
        started.continuation.yield()
        let stalledStream = AsyncStream<ByteBuffer> { _ in }
        return HTTPClientResponse(
          version: .http1_1,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .stream(stalledStream)
        )
      }
    ])
    let client = AuthHTTPClient(mock: mock)

    let requestTask = Task {
      let _: MockTokenResponse = try await client.get(url: targetURL, timeout: .seconds(10))
    }

    var iterator = started.stream.makeAsyncIterator()
    _ = await iterator.next()
    requestTask.cancel()

    await #expect(throws: CancellationError.self) {
      try await requestTask.value
    }
  }

  @Test func clientEnforcesTimeoutAcrossStalledResponseBody() async throws {
    let targetURL = URL(string: "http://metadata.google.internal/token")!
    let mock = MockHTTPClient([
      { _ in
        let stalledStream = AsyncStream<ByteBuffer> { _ in }
        return HTTPClientResponse(
          version: .http1_1,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .stream(stalledStream)
        )
      },
      { _ in
        let stalledStream = AsyncStream<ByteBuffer> { _ in }
        return HTTPClientResponse(
          version: .http1_1,
          status: .serviceUnavailable,
          headers: .init([("Metadata-Flavor", "Google")]),
          body: .stream(stalledStream)
        )
      },
    ])
    let client = AuthHTTPClient(mock: mock)

    let okError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(
        url: targetURL,
        timeout: .milliseconds(40)
      )
    }
    #expect(okError?.urlError?.code == .timedOut)

    let non2xxError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(
        url: targetURL,
        timeout: .milliseconds(40)
      )
    }
    #expect(non2xxError?.statusCode == 503)
    #expect(non2xxError?.headers?["Metadata-Flavor"] == "Google")
    #expect(non2xxError?.bodyData == Data())
  }

  @Test func clientPreservesUnsuccessfulResponseOnOversizedErrorBody() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let oversizedData = Data(repeating: 0x41, count: AuthHTTPClient.maxResponseSize + 1)

    let makeResponse: @Sendable (HTTPResponseStatus) -> MockHTTPClient.Closure = { status in
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: status,
          headers: .init([("X-Debug-Header", "OversizedError")]),
          body: .bytes(.init(data: oversizedData)),
        )
      }
    }

    let client = AuthHTTPClient(
      mock: MockHTTPClient([
        makeResponse(.badRequest),
        makeResponse(.forbidden),
        makeResponse(.badRequest),
        makeResponse(.forbidden),
        makeResponse(.tooManyRequests),
        makeResponse(.serviceUnavailable),
      ])
    )

    let getError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    #expect(getError?.statusCode == 400)
    #expect(getError?.isRetryable == false)
    #expect(getError?.bodyData == Data())
    #expect(getError?.body == "")
    #expect(getError?.description == "HTTP status 400")
    #expect(getError?.headers?["X-Debug-Header"] == "OversizedError")

    let getStringError = await #expect(throws: AuthHTTPError.self) {
      _ = try await client.getString(url: targetURL)
    }
    #expect(getStringError?.statusCode == 403)
    #expect(getStringError?.isRetryable == false)
    #expect(getStringError?.bodyData == Data())
    #expect(getStringError?.body == "")
    #expect(getStringError?.headers?["X-Debug-Header"] == "OversizedError")

    let postError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.post(
        url: targetURL,
        body: ["grant_type": "refresh_token"]
      )
    }
    #expect(postError?.statusCode == 400)
    #expect(postError?.isRetryable == false)
    #expect(postError?.bodyData == Data())
    #expect(postError?.body == "")

    let postDataError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.postData(
        url: targetURL,
        bodyData: Data("grant_type=refresh_token".utf8),
        contentType: "application/x-www-form-urlencoded"
      )
    }
    #expect(postDataError?.statusCode == 403)
    #expect(postDataError?.isRetryable == false)
    #expect(postDataError?.bodyData == Data())
    #expect(postDataError?.body == "")

    let rateLimitedError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    #expect(rateLimitedError?.statusCode == 429)
    #expect(rateLimitedError?.isRetryable == true)
    #expect(rateLimitedError?.bodyData == Data())

    let serverError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    #expect(serverError?.statusCode == 503)
    #expect(serverError?.isRetryable == true)
    #expect(serverError?.bodyData == Data())
  }

  @Test func clientPreservesUnsuccessfulResponseOnFailingErrorBodyStream() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let makeFailingStreamResponse: MockHTTPClient.Closure = { _ in
      let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
        continuation.yield(ByteBuffer(string: #"{"error":"partial"#))
        continuation.finish(throwing: URLError(.networkConnectionLost))
      }
      return HTTPClientResponse(
        version: .http2,
        status: .forbidden,
        headers: .init([("X-Error-Source", "IAM")]),
        body: .stream(stream)
      )
    }

    let client = AuthHTTPClient(
      mock: MockHTTPClient([
        makeFailingStreamResponse,
        makeFailingStreamResponse,
        makeFailingStreamResponse,
        makeFailingStreamResponse,
      ])
    )

    let getError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    #expect(getError?.statusCode == 403)
    #expect(getError?.isRetryable == false)
    #expect(getError?.urlError == nil)
    #expect(getError?.bodyData == Data())
    #expect(getError?.headers?["X-Error-Source"] == "IAM")

    let getStringError = await #expect(throws: AuthHTTPError.self) {
      _ = try await client.getString(url: targetURL)
    }
    #expect(getStringError?.statusCode == 403)
    #expect(getStringError?.isRetryable == false)
    #expect(getStringError?.urlError == nil)
    #expect(getStringError?.bodyData == Data())

    let postError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.post(
        url: targetURL,
        body: ["grant_type": "refresh_token"]
      )
    }
    #expect(postError?.statusCode == 403)
    #expect(postError?.isRetryable == false)
    #expect(postError?.urlError == nil)
    #expect(postError?.bodyData == Data())

    let postDataError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.postData(
        url: targetURL,
        bodyData: Data("grant_type=refresh_token".utf8),
        contentType: "application/x-www-form-urlencoded"
      )
    }
    #expect(postDataError?.statusCode == 403)
    #expect(postDataError?.isRetryable == false)
    #expect(postDataError?.urlError == nil)
    #expect(postDataError?.bodyData == Data())
  }

  @Test func clientReleasesResponseBodyAndHistoryOnUnsuccessfulResponse() async throws {
    final class TrackedOversizedSequence: AsyncSequence, Sendable {
      typealias Element = ByteBuffer

      struct AsyncIterator: AsyncIteratorProtocol {
        var remainingChunks = 2
        mutating func next() async throws -> ByteBuffer? {
          guard remainingChunks > 0 else { return nil }
          remainingChunks -= 1
          return ByteBuffer(repeating: 0x41, count: AuthHTTPClient.maxResponseSize)
        }
      }

      func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator()
      }
    }

    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    weak var weakSequence: TrackedOversizedSequence?

    let client: AuthHTTPClient = {
      let sequence = TrackedOversizedSequence()
      weakSequence = sequence
      var echoedRequest = HTTPClientRequest(url: targetURL.absoluteString)
      echoedRequest.headers.add(name: "Authorization", value: "Bearer secret-request-token")
      let historyEntry = HTTPClientRequestResponse(
        request: echoedRequest,
        responseHead: .init(version: .http2, status: .forbidden)
      )
      let response = HTTPClientResponse(
        version: .http2,
        status: .forbidden,
        headers: .init([("X-Debug-Header", "Detached")]),
        body: .stream(sequence),
        history: [historyEntry]
      )
      return AuthHTTPClient(mock: MockHTTPClient([{ _ in response }]))
    }()

    let caughtError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }

    // Even while the caller (or `TokenCache.permanentError`) retains `caughtError`, the live
    // response body sequence and request/redirect history must already be released.
    withExtendedLifetime(caughtError) {
      #expect(weakSequence == nil)
      guard case .unsuccessfulResponse(let storedResponse, _) = caughtError else {
        Issue.record("Expected unsuccessfulResponse, got \(String(describing: caughtError))")
        return
      }
      #expect(storedResponse.status == .forbidden)
      #expect(storedResponse.headers["X-Debug-Header"] == ["Detached"])
      #expect(storedResponse.history.isEmpty)
    }
  }

  @Test func clientThrowsOnOversizedSuccessBody() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let oversizedData = Data(repeating: 0x41, count: AuthHTTPClient.maxResponseSize + 1)
    let makeOversizedOK: MockHTTPClient.Closure = { _ in
      HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: oversizedData)),
      )
    }

    let client = AuthHTTPClient(
      mock: MockHTTPClient([makeOversizedOK, makeOversizedOK, makeOversizedOK, makeOversizedOK])
    )

    let getError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
    guard case .unknown(let getUnderlying) = getError else {
      Issue.record("Expected AuthHTTPError.unknown, got \(String(describing: getError))")
      return
    }
    #expect(getUnderlying is NIOTooManyBytesError)
    #expect(getError?.statusCode == nil)
    #expect(getError?.isRetryable == true)

    let getStringError = await #expect(throws: AuthHTTPError.self) {
      _ = try await client.getString(url: targetURL)
    }
    guard case .unknown(let getStringUnderlying) = getStringError else {
      Issue.record("Expected AuthHTTPError.unknown, got \(String(describing: getStringError))")
      return
    }
    #expect(getStringUnderlying is NIOTooManyBytesError)
    #expect(getStringError?.statusCode == nil)
    #expect(getStringError?.isRetryable == true)

    let postError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.post(
        url: targetURL,
        body: ["grant_type": "refresh_token"]
      )
    }
    guard case .unknown(let postUnderlying) = postError else {
      Issue.record("Expected AuthHTTPError.unknown, got \(String(describing: postError))")
      return
    }
    #expect(postUnderlying is NIOTooManyBytesError)
    #expect(postError?.statusCode == nil)
    #expect(postError?.isRetryable == true)

    let postDataError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.postData(
        url: targetURL,
        bodyData: Data("grant_type=refresh_token".utf8),
        contentType: "application/x-www-form-urlencoded"
      )
    }
    guard case .unknown(let postDataUnderlying) = postDataError else {
      Issue.record("Expected AuthHTTPError.unknown, got \(String(describing: postDataError))")
      return
    }
    #expect(postDataUnderlying is NIOTooManyBytesError)
    #expect(postDataError?.statusCode == nil)
    #expect(postDataError?.isRetryable == true)
  }

  @Test func clientPropagatesCancellationAcrossRequestAndBodyStages() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let (reqStarted, reqStartedCont) = AsyncStream<Void>.makeStream()
    let (reqCancelled, reqCancelledCont) = AsyncStream<Void>.makeStream()
    let (okBodyStarted, okBodyStartedCont) = AsyncStream<Void>.makeStream()
    let (okBodyCancelled, okBodyCancelledCont) = AsyncStream<Void>.makeStream()
    let (errBodyStarted, errBodyStartedCont) = AsyncStream<Void>.makeStream()
    let (errBodyCancelled, errBodyCancelledCont) = AsyncStream<Void>.makeStream()

    let mock = MockHTTPClient([
      // 1. Direct CancellationError during `performRequest`
      { _ in
        throw CancellationError()
      },
      // 2. Direct CancellationError during 2xx response body collection
      { _ in
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
          continuation.finish(throwing: CancellationError())
        }
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          body: .stream(stream)
        )
      },
      // 3. Direct CancellationError during non-2xx error body collection
      { _ in
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
          continuation.finish(throwing: CancellationError())
        }
        return HTTPClientResponse(
          version: .http2,
          status: .badRequest,
          body: .stream(stream)
        )
      },
      // 4. Transport teardown error after task cancellation during `performRequest`
      { _ in
        reqStartedCont.finish()
        for await _ in reqCancelled {}
        throw URLError(.cancelled)
      },
      // 5. Transport teardown error after task cancellation during 2xx body collection
      { _ in
        okBodyStartedCont.finish()
        for await _ in okBodyCancelled {}
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
          continuation.finish(throwing: URLError(.cancelled))
        }
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          body: .stream(stream)
        )
      },
      // 6. Transport teardown error after task cancellation during non-2xx error body collection
      { _ in
        errBodyStartedCont.finish()
        for await _ in errBodyCancelled {}
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
          continuation.finish(throwing: URLError(.cancelled))
        }
        return HTTPClientResponse(
          version: .http2,
          status: .badRequest,
          body: .stream(stream)
        )
      },
    ])

    let client = AuthHTTPClient(mock: mock)

    for _ in 0..<3 {
      await #expect(throws: CancellationError.self) {
        let _: MockTokenResponse = try await client.get(url: targetURL)
      }
    }

    for (started, cancelledCont) in [
      (reqStarted, reqCancelledCont),
      (okBodyStarted, okBodyCancelledCont),
      (errBodyStarted, errBodyCancelledCont),
    ] {
      let task = Task {
        let _: MockTokenResponse = try await client.get(url: targetURL)
      }
      for await _ in started {}
      task.cancel()
      cancelledCont.finish()
      await #expect(throws: CancellationError.self) {
        try await task.value
      }
    }
  }

  @Test func clientTimesOutWhenHeadersArriveAfterDeadline() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let okBody = Data(#"{"access_token": "tok", "expires_in": 3600}"#.utf8)
    let errBody = Data(#"{"error": "server_error"}"#.utf8)
    let mock = MockHTTPClient([
      { _ in
        try await Task.sleep(for: .milliseconds(30))
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: okBody))
        )
      },
      { _ in
        try await Task.sleep(for: .milliseconds(30))
        return HTTPClientResponse(
          version: .http2,
          status: .serviceUnavailable,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: errBody))
        )
      },
    ])

    let client = AuthHTTPClient(mock: mock)

    let okTimeoutError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(
        url: targetURL,
        timeout: .milliseconds(10)
      )
    }
    guard case let .transportError(urlError) = okTimeoutError else {
      Issue.record(
        "Expected AuthHTTPError.transportError, got \(String(describing: okTimeoutError))")
      return
    }
    #expect(urlError.code == .timedOut)

    let errTimeoutError = await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(
        url: targetURL,
        timeout: .milliseconds(10)
      )
    }
    #expect(errTimeoutError?.statusCode == 503)
    #expect(errTimeoutError?.bodyData == Data())
  }

  @Test func defaultInitializerSharesProcessWidePool() throws {
    let client1 = AuthHTTPClient()
    let client2 = AuthHTTPClient()
    let mdsProvider = MDSAccessTokenProvider()

    let shared1 = try #require(client1.inner as? SharedHTTPClient)
    let shared2 = try #require(client2.inner as? SharedHTTPClient)
    let mdsShared = try #require(mdsProvider.client.inner as? SharedHTTPClient)

    #expect(shared1.inner === SharedHTTPClient.defaultClient)
    #expect(shared2.inner === SharedHTTPClient.defaultClient)
    #expect(mdsShared.inner === SharedHTTPClient.defaultClient)
    #expect(shared1.inner !== HTTPClient.shared)
  }

  @Test func customHTTPClientInjectionAndLoopbackExecution() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(LoopbackTokenServerHandler())
        }
      }

    let customHTTPClient = HTTPClient(eventLoopGroup: group)
    var serverChannel: (any Channel)? = nil
    let result: Result<Void, any Error>
    do {
      let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
      serverChannel = channel
      let port = try #require(channel.localAddress?.port)
      let tokenURL = try #require(URL(string: "http://127.0.0.1:\(port)/token"))
      let mdsURL = try #require(URL(string: "http://127.0.0.1:\(port)/mds"))

      // 1. Default AuthHTTPClient() executes via SharedHTTPClient.defaultClient without injecting Accept-Encoding.
      let defaultAuthClient = AuthHTTPClient()
      let echoAcceptEncoding = try await defaultAuthClient.getString(
        url: mdsURL,
        headers: ["Metadata-Flavor": "Google"],
        timeout: .seconds(10)
      )
      #expect(echoAcceptEncoding == "<none>")

      // 2. Custom HTTPClient injection executes via the supplied HTTPClient instance.
      let injectedAuthClient = AuthHTTPClient(customHTTPClient)
      let injectedShared = try #require(injectedAuthClient.inner as? SharedHTTPClient)
      #expect(injectedShared.inner === customHTTPClient)
      #expect(injectedShared.inner !== SharedHTTPClient.defaultClient)

      let tokenResponse: MockTokenResponse = try await injectedAuthClient.post(
        url: tokenURL,
        body: ["grant_type": "refresh_token"],
        timeout: .seconds(10)
      )
      #expect(tokenResponse == MockTokenResponse(accessToken: "loopback-token", expiresIn: 3600))
      result = .success(())
    } catch {
      result = .failure(error)
    }

    try? await serverChannel?.close().get()
    switch result {
    case .success:
      do {
        try await customHTTPClient.shutdown()
      } catch {
        try? await group.shutdownGracefully()
        throw error
      }
      try await group.shutdownGracefully()
    case .failure(let error):
      try? await customHTTPClient.shutdown()
      try? await group.shutdownGracefully()
      throw error
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func defaultClientDoesNotFollowGetRedirects(statusCode: UInt) async throws {
    try await withRedirectLoopbackServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirected".utf8),
      contentType: "text/plain; charset=utf-8"
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let sourceURL = try #require(URL(string: "http://127.0.0.1:\(sourcePort)/mds"))
      let targetURL = try #require(URL(string: "http://127.0.0.1:\(targetPort)/redirect-target"))
      let client = AuthHTTPClient()

      let error = await #expect(throws: AuthHTTPError.self) {
        _ = try await client.getString(
          url: sourceURL,
          headers: ["Metadata-Flavor": "Google"],
          timeout: .seconds(10)
        )
      }

      guard case let .unsuccessfulResponse(response, data) = error else {
        Issue.record(
          "Expected AuthHTTPError.unsuccessfulResponse, got \(String(describing: error))")
        return
      }
      #expect(response.status.code == statusCode)
      #expect(response.headers.first(name: "Location") == targetURL.absoluteString)
      #expect(String(data: data, encoding: .utf8) == "redirected")

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .GET)
      #expect(sourceRequests.first?.uri == "/mds")
      #expect(sourceRequests.first?.headers["Metadata-Flavor"] == ["Google"])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func defaultClientDoesNotFollowPostRedirects(statusCode: UInt) async throws {
    try await withRedirectLoopbackServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data(#"{"error": "redirected"}"#.utf8),
      contentType: "application/json"
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let sourceURL = try #require(URL(string: "http://127.0.0.1:\(sourcePort)/token"))
      let targetURL = try #require(URL(string: "http://127.0.0.1:\(targetPort)/redirect-target"))
      let client = AuthHTTPClient()

      let error = await #expect(throws: AuthHTTPError.self) {
        let _: MockTokenResponse = try await client.post(
          url: sourceURL,
          body: ["grant_type": "refresh_token", "refresh_token": "test-refresh-token"],
          timeout: .seconds(10)
        )
      }

      guard case let .unsuccessfulResponse(response, _) = error else {
        Issue.record(
          "Expected AuthHTTPError.unsuccessfulResponse, got \(String(describing: error))")
        return
      }
      #expect(response.status.code == statusCode)
      #expect(response.headers.first(name: "Location") == targetURL.absoluteString)

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .POST)
      #expect(sourceRequests.first?.uri == "/token")
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func defaultClientDoesNotFollowPostDataRedirects(statusCode: UInt) async throws {
    try await withRedirectLoopbackServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data(#"{"error": "redirected"}"#.utf8),
      contentType: "application/json"
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let sourceURL = try #require(URL(string: "http://127.0.0.1:\(sourcePort)/v1/token"))
      let targetURL = try #require(URL(string: "http://127.0.0.1:\(targetPort)/redirect-target"))
      let client = AuthHTTPClient()
      let payload = Data("grant_type=urn:ietf:params:oauth:grant-type:token-exchange".utf8)

      let error = await #expect(throws: AuthHTTPError.self) {
        let _: MockTokenResponse = try await client.postData(
          url: sourceURL,
          bodyData: payload,
          contentType: "application/x-www-form-urlencoded",
          headers: ["x-test-header": "test-value"],
          timeout: .seconds(10)
        )
      }

      guard case let .unsuccessfulResponse(response, _) = error else {
        Issue.record(
          "Expected AuthHTTPError.unsuccessfulResponse, got \(String(describing: error))")
        return
      }
      #expect(response.status.code == statusCode)
      #expect(response.headers.first(name: "Location") == targetURL.absoluteString)

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .POST)
      #expect(sourceRequests.first?.uri == "/v1/token")
      #expect(sourceRequests.first?.body == payload)
      #expect(
        sourceRequests.first?.headers["Content-Type"] == ["application/x-www-form-urlencoded"])
      #expect(sourceRequests.first?.headers["x-test-header"] == ["test-value"])
      #expect(targetRecorder.requests.isEmpty)
    }
  }
}

private struct RedirectRecordedRequest: Sendable {
  let method: HTTPMethod
  let uri: String
  let headers: HTTPHeaders
  let body: Data
}

private final class RedirectRequestRecorder: Sendable {
  private let recorded = Mutex<[RedirectRecordedRequest]>([])

  func record(_ request: RedirectRecordedRequest) {
    self.recorded.withLock { $0.append(request) }
  }

  var requests: [RedirectRecordedRequest] {
    self.recorded.withLock { $0 }
  }
}

private func withRedirectLoopbackServers<T>(
  status: HTTPResponseStatus,
  responseBody: Data,
  contentType: String,
  _ operation: (
    _ sourcePort: Int,
    _ targetPort: Int,
    _ sourceRecorder: RedirectRequestRecorder,
    _ targetRecorder: RedirectRequestRecorder
  ) async throws -> T
) async throws -> T {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  let sourceRecorder = RedirectRequestRecorder()
  let targetRecorder = RedirectRequestRecorder()

  var sourceChannel: (any Channel)? = nil
  var targetChannel: (any Channel)? = nil
  let result: Result<T, any Error>
  do {
    let targetBootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(
            RedirectStaticServerHandler(
              status: .ok,
              headers: HTTPHeaders([("Content-Type", "application/json")]),
              body: Data(#"{"status": "unexpected"}"#.utf8),
              recorder: targetRecorder
            )
          )
        }
      }
    let boundTarget = try await targetBootstrap.bind(host: "127.0.0.1", port: 0).get()
    targetChannel = boundTarget
    let targetPort = try #require(boundTarget.localAddress?.port)

    let sourceHeaders = HTTPHeaders([
      ("Location", "http://127.0.0.1:\(targetPort)/redirect-target"),
      ("Content-Type", contentType),
    ])
    let sourceBootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(
            RedirectStaticServerHandler(
              status: status,
              headers: sourceHeaders,
              body: responseBody,
              recorder: sourceRecorder
            )
          )
        }
      }
    let boundSource = try await sourceBootstrap.bind(host: "127.0.0.1", port: 0).get()
    sourceChannel = boundSource
    let sourcePort = try #require(boundSource.localAddress?.port)

    result = .success(try await operation(sourcePort, targetPort, sourceRecorder, targetRecorder))
  } catch {
    result = .failure(error)
  }

  try? await sourceChannel?.close().get()
  try? await targetChannel?.close().get()
  switch result {
  case .success(let value):
    try await group.shutdownGracefully()
    return value
  case .failure(let error):
    try? await group.shutdownGracefully()
    throw error
  }
}

private final class RedirectStaticServerHandler: ChannelInboundHandler {
  typealias InboundIn = NIOHTTPServerRequestFull
  typealias OutboundOut = HTTPServerResponsePart

  private let status: HTTPResponseStatus
  private let headers: HTTPHeaders
  private let body: Data
  private let recorder: RedirectRequestRecorder

  init(
    status: HTTPResponseStatus,
    headers: HTTPHeaders,
    body: Data,
    recorder: RedirectRequestRecorder
  ) {
    self.status = status
    self.headers = headers
    self.body = body
    self.recorder = recorder
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let request = self.unwrapInboundIn(data)
    self.recorder.record(
      RedirectRecordedRequest(
        method: request.head.method,
        uri: request.head.uri,
        headers: request.head.headers,
        body: request.body.map { Data(buffer: $0) } ?? Data()
      )
    )
    var responseHeaders = self.headers
    responseHeaders.replaceOrAdd(name: "Content-Length", value: "\(self.body.count)")
    responseHeaders.replaceOrAdd(name: "Connection", value: "close")
    let head = HTTPResponseHead(
      version: request.head.version,
      status: self.status,
      headers: responseHeaders
    )
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    if !self.body.isEmpty {
      let buffer = context.channel.allocator.buffer(data: self.body)
      context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    }
    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
  }
}

private final class LoopbackTokenServerHandler: ChannelInboundHandler {
  typealias InboundIn = NIOHTTPServerRequestFull
  typealias OutboundOut = HTTPServerResponsePart

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let request = self.unwrapInboundIn(data)
    var headers = HTTPHeaders()
    let payload: Data

    if request.head.uri == "/mds" {
      let acceptEncoding = request.head.headers["Accept-Encoding"].joined(separator: ", ")
      payload = Data((acceptEncoding.isEmpty ? "<none>" : acceptEncoding).utf8)
      headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
    } else {
      payload = Data(#"{"access_token": "loopback-token", "expires_in": 3600}"#.utf8)
      headers.add(name: "Content-Type", value: "application/json")
    }

    headers.add(name: "Content-Length", value: "\(payload.count)")
    let head = HTTPResponseHead(version: request.head.version, status: .ok, headers: headers)
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)

    let body = context.channel.allocator.buffer(data: payload)
    context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
  }
}

private struct MockTokenResponse: Codable, Sendable, Equatable {
  let accessToken: String
  let expiresIn: Int
}
