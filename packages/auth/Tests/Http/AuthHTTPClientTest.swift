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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

@testable import GoogleCloudAuth

// MARK: - Mock Response Model

private struct MockTokenResponse: Codable, Sendable, Equatable {
  let accessToken: String
  let expiresIn: Int
}

// MARK: - Mock URL Protocol for Mocking Network Requests

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler:
    (@Sendable (URLRequest) throws -> (URLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      fatalError("Handler is not set.")
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

// MARK: - Suite: AuthHTTPClient Test

// Serialized because MockURLProtocol uses a shared static requestHandler.
@Suite(.serialized) struct AuthHTTPClientTest {
  private let mockSession: URLSession

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    self.mockSession = URLSession(configuration: config)
  }

  @Test func clientPerformsGetAndDecodesSnakeCase() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-token-123", expiresIn: 3600)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "GET")
      #expect(request.value(forHTTPHeaderField: "X-Goog-Custom-Header") == "HeaderValue")
      #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
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

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let response: MockTokenResponse = try await client.post(
      url: targetURL,
      body: ["grant_type": "refresh_token"]
    )

    #expect(response == mockPayload)
  }

  @Test func clientThrowsHTTPStatusCodeError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/invalid")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 503,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      return (response, Data())
    }

    let client = AuthHTTPClient(session: self.mockSession)

    await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
  }

  @Test func clientPerformsGetAndReturnsPlainTextString() async throws {
    let targetURL = URL(string: "http://metadata.google.internal/email")!
    let mockEmail = "test-service-account@google.com"
    let mockData = Data(mockEmail.utf8)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "GET")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      return (response, mockData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let result = try await client.getString(
      url: targetURL,
      headers: ["Metadata-Flavor": "Google"]
    )

    #expect(result == mockEmail)
  }

  @Test func clientThrowsNetworkError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      throw URLError(.notConnectedToInternet)
    }

    let client = AuthHTTPClient(session: self.mockSession)

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

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      return (response, mockData)
    }

    let client = AuthHTTPClient(session: self.mockSession)

    await #expect(throws: AuthHTTPError.self) {
      try await client.getString(url: targetURL)
    }
  }

  @Test func clientPerformsPostWithCustomHeaders() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mockPayload = MockTokenResponse(accessToken: "fake-post-token", expiresIn: 1800)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "CustomValue")

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let response: MockTokenResponse = try await client.post(
      url: targetURL,
      body: ["grant_type": "refresh_token"],
      headers: ["X-Custom-Header": "CustomValue"]
    )

    #expect(response == mockPayload)
  }

  @Test func clientThrowsOnNonHTTPResponse() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = URLResponse(
        url: targetURL,
        mimeType: nil,
        expectedContentLength: 0,
        textEncodingName: nil
      )
      return (response, Data())
    }

    let client = AuthHTTPClient(session: self.mockSession)

    await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
  }

  @Test func clientThrowsOnEmptyHTTPResponse() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data())
    }

    let client = AuthHTTPClient(session: self.mockSession)
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

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")
      #expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
      #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "Val")

      #expect(request.bodyData == postBody)

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let response: MockTokenResponse = try await client.postData(
      url: targetURL,
      bodyData: postBody,
      contentType: "application/x-www-form-urlencoded",
      headers: ["X-Custom-Header": "Val"]
    )

    #expect(response == mockPayload)
  }
}
