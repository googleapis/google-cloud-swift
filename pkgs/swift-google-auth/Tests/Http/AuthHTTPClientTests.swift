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
import Testing
import AsyncHTTPClient
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
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        return HTTPClientResponse(
          version: .http2,
          status: .serviceUnavailable,
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    await #expect(throws: AuthHTTPError.self) {
      let _: MockTokenResponse = try await client.get(url: targetURL)
    }
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
  }
}

private struct MockTokenResponse: Codable, Sendable, Equatable {
  let accessToken: String
  let expiresIn: Int
}
