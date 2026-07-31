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
@testable import GoogleCloudAuth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      fatalError("Handler is unavailable.")
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

@Suite(.serialized) struct MDSCredentialsTest {
  private let mockSession: URLSession

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    self.mockSession = URLSession(configuration: config)
  }

  @Test func headersSuccessWithQuotaProject() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!

    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
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
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?scopes=scope1,scope2"
    )!

    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      #expect(request.url?.query == "scopes=scope1,scope2")
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(
      scopes: ["scope1", "scope2"], client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func gceMetadataHostEnvVar() async throws {
    let targetURL = URL(
      string: "http://127.0.0.1:8080/computeMetadata/v1/instance/service-accounts/default/token"
    )!

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

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let response = HTTPURLResponse(
        url: targetURL, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      return (response, encodedData)
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(
      client: client, environment: ["GCE_METADATA_HOST": "127.0.0.1:8080"])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-override-token" },
      "Missing authorization header in \(headers) for overridden MDS host"
    )
  }

  @Test func mdsProviderUniverseDomainIsNil() async throws {
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(client: client, environment: [:])
    let ud = await provider.universeDomain()
    #expect(ud == nil, "Universe domain should be nil for MDS provider")
  }

  @Test func adcNoMDS() async throws {
    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      throw URLError(.cannotConnectToHost)
    }
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(client: client, fromADC: true, environment: [:])
    let error = await #expect(throws: CredentialsError.self) { _ = try await provider.headers() }

    if let error = error {
      #expect(
        error.localizedDescription.contains("application-default"),
        "Localized description lacks application-default troubleshooting context: \(error.localizedDescription)"
      )

      if case let .missingEnvironmentConfiguration(payload) = error {
        #expect(
          payload.contains("GCE_METADATA_HOST"),
          "Error payload lacks specific environment diagnostic info: \(payload)"
        )
      }
    }
  }

  @Test func adcOverriddenMDS() async throws {
    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      throw URLError(.cannotConnectToHost)
    }
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(
      client: client, fromADC: true, environment: ["GCE_METADATA_HOST": "127.0.0.1:8080"])
    let error = await #expect(throws: AuthHTTPError.self) { _ = try await provider.headers() }
    if case let .transportError(urlError) = error {
      #expect(
        urlError.code == .cannotConnectToHost, "Expected cannotConnectToHost, got \(urlError.code)")
    }
  }

  @Test func retriesOnTransientFailures() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encodedData = try JSONEncoder().encode(mockPayload)

    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let count = attempts.increment()
      if count < 3 {
        return (
          HTTPURLResponse(url: targetURL, statusCode: 503, httpVersion: nil, headerFields: nil)!,
          Data()
        )
      }
      return (
        HTTPURLResponse(
          url: targetURL, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, encodedData
      )
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
    let count = attempts.getCount()
    #expect(count == 3, "Expected exactly 3 execution attempts, got \(count)")
  }

  @Test func retriesForSuccess() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let count = attempts.increment()
      if count == 1 {
        return (
          HTTPURLResponse(url: targetURL, statusCode: 500, httpVersion: nil, headerFields: nil)!,
          Data()
        )
      }
      return (
        HTTPURLResponse(
          url: targetURL, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, encodedData
      )
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
    let count = attempts.getCount()
    #expect(count == 2, "Expected exactly 2 execution attempts, got \(count)")
  }

  @Test func doesNotRetryOnNonTransientFailures() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!
    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let _ = attempts.increment()
      return (
        HTTPURLResponse(url: targetURL, statusCode: 404, httpVersion: nil, headerFields: nil)!,
        Data()
      )
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])

    await #expect(throws: AuthHTTPError.self) {
      _ = try await provider.headers()
    }
    let count = attempts.getCount()
    #expect(count == 1, "Expected no retries on permanent HTTP 404 error, got \(count) calls")
  }

  @Test func tokenCaching() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let networkCalls = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let _ = networkCalls.increment()
      return (
        HTTPURLResponse(
          url: targetURL, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, encodedData
      )
    }

    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(client: client, environment: [:])

    _ = try await provider.headers()
    _ = try await provider.headers()
    _ = try await provider.headers()

    let count = networkCalls.getCount()
    #expect(
      count == 1, "Expected exactly 1 network request due to proactive actor caching, got \(count)")
  }

  @Test func retriesOnTransientNetworkErrors() async throws {
    let targetURL = URL(
      string:
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == "/computeMetadata/v1/instance/service-accounts/default/token")
      #expect(request.value(forHTTPHeaderField: "Metadata-Flavor") == "Google")
      let count = attempts.increment()
      if count == 1 {
        throw URLError(.timedOut)
      }
      return (
        HTTPURLResponse(
          url: targetURL, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!, encodedData
      )
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(session: self.mockSession)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer mock-token" },
      "Missing authorization header in \(headers)"
    )
    let count = attempts.getCount()
    #expect(count == 2, "Expected exactly 2 execution attempts, got \(count)")
  }
}
