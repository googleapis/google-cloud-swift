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
import AsyncHTTPClient
import NIOHTTP1
import Testing
@testable import GoogleCloudAuth

@Suite struct MDSCredentialsTest {
  @Test func headersSuccessWithQuotaProject() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      quotaProjectID: "my-quota-project", client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
    #expect(
      headers.contains { $0.0 == "X-Goog-User-Project" && $0.1 == "my-quota-project" },
      "Missing quota project ID header in \(headers)"
    )
  }

  @Test func headersSuccessWithScopes() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.method == .GET)
        let url = URL(string: request.url)!
        #expect(url.path == "/computeMetadata/v1/instance/service-accounts/default/token")
        #expect(url.query == "scopes=scope1,scope2")
        #expect(request.headers["Metadata-Flavor"] == ["Google"])
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      scopes: ["scope1", "scope2"], client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func gceMetadataHostEnvVar() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(
      accessToken: "mock-override-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, environment: ["GCE_METADATA_HOST": "127.0.0.1:8080"])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-override-token" },
      "Missing authorization header in \(headers) for overridden MDS host"
    )
  }

  @Test func mdsProviderUniverseDomainIsNil() async throws {
    let mock = MockHTTPClient([])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(client: client, environment: [:])
    let ud = await provider.universeDomain()
    #expect(ud == nil, "Universe domain should be nil for MDS provider")
  }

  @Test func adcNoMDS() async throws {
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        throw URLError(.cannotConnectToHost)
      }
    ])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(client: client, fromADC: true, environment: [:])
    let error = await #expect(throws: CredentialsError.self) { _ = try await provider.headers() }

    if case let .cannotFetchToken(adc, env, _) = error {
      #expect(adc == true, "Error details: \(error)")
      #expect(env == nil, "Error details: \(error)")
    } else {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test func adcOverriddenMDS() async throws {
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        throw URLError(.cannotConnectToHost)
      }
    ])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, fromADC: true, environment: ["GCE_METADATA_HOST": "127.0.0.1:1"])
    let credentialsError = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    let error = #expect(throws: AuthHTTPError.self) {
      if case let .cannotFetchToken(_, _, source) = credentialsError {
        throw source
      }
    }
    if case let .transportError(urlError) = error {
      #expect(
        urlError.code == .cannotConnectToHost, "Expected cannotConnectToHost, got \(urlError.code)")
    }
  }

  @Test func retriesOnTransientFailures() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encodedData = try JSONEncoder().encode(mockPayload)

    let unavailable = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: .serviceUnavailable)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([unavailable, unavailable, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func retriesForSuccess() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let internalError = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: .internalServerError)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([internalError, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func doesNotRetryOnNonTransientFailures() async throws {
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        let _ = attempts.increment()
        return HTTPClientResponse(version: .http2, status: .notFound, )
      }
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    guard case let .cannotFetchToken(_, _, source) = error else {
      Issue.record("expected a .cannotFetchToken error, got=\(error)")
      return
    }
    #expect(source is AuthHTTPError, "expected AuthHTTPError as the source, got \(source)")
    let count = attempts.getCount()
    #expect(count == 1, "Expected no retries on permanent HTTP 404 error, got \(count) calls")
  }

  @Test func tokenCaching() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let networkCalls = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        let _ = networkCalls.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(client: client, environment: [:])

    _ = try await provider.headers()
    _ = try await provider.headers()
    _ = try await provider.headers()

    let count = networkCalls.getCount()
    #expect(
      count == 1, "Expected exactly 1 network request due to proactive actor caching, got \(count)")
  }

  @Test func retriesOnTransientNetworkErrors() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let timeout = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw URLError(.timedOut)
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }
    let mock = MockHTTPClient([timeout, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test(arguments: [
    HTTPResponseStatus.internalServerError,  // 500
    .notImplemented,  // 501
    .badGateway,  // 502
    .serviceUnavailable,  // 503
    .gatewayTimeout,  // 504
    .httpVersionNotSupported,  // 505
    .requestTimeout,  // 408
    .tooManyRequests,  // 429
  ])
  func retriesOnSpecificTransientStatusCodes(status: HTTPResponseStatus) async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encodedData = try JSONEncoder().encode(mockPayload)

    let failure = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: status)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([failure, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test(arguments: [
    HTTPResponseStatus.badRequest,  // 400
    .unauthorized,  // 401
    .forbidden,  // 403
    .notFound,  // 404
  ])
  func doesNotRetryOnSpecificNonTransientStatusCodes(status: HTTPResponseStatus) async throws {
    let failure = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: status)
    }
    let mock = MockHTTPClient([failure])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])

    await #expect(throws: Error.self) {
      _ = try await provider.headers()
    }
  }

  @Test func retriesOnConnectionReset() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let connectionReset = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw URLError(.networkConnectionLost)
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([connectionReset, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func retriesOnIncompleteMessage() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let incompleteMessage = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw HTTPClientError.remoteConnectionClosed
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }
    let mock = MockHTTPClient([incompleteMessage, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  static func checkRequest(
    _ request: HTTPClientRequest, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(request.method == .GET)
    let url = URL(string: request.url)!
    #expect(
      url.path == "/computeMetadata/v1/instance/service-accounts/default/token",
      sourceLocation: sourceLocation)
    #expect(request.headers["Metadata-Flavor"] == ["Google"], sourceLocation: sourceLocation)
  }
}
