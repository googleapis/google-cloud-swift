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
}

private struct MockTokenResponse: Codable, Sendable, Equatable {
  let accessToken: String
  let expiresIn: Int
}
