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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
@testable import GoogleCloudAuth

typealias UserCredentials = UserCredentialsGeneric<TestClock>

@Suite(.serialized) struct UserCredentialsTest {
  private let mockSession: URLSession

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    self.mockSession = URLSession(configuration: config)
  }

  @Test func userProviderHeadersAndUniverseDomain() async throws {
    let targetURL = URL(string: "https://mock.example.com")!
    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data("{}".utf8))
    }

    let mockData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token",
      tokenUri: "https://mock.example.com",
      quotaProjectId: "mock-project"
    )

    let provider = try UserCredentials(
      user: mockData,
      universeDomain: defaultUniverseDomain,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    // Trigger headers to ensure background task is resolved or handled
    _ = try? await provider.headers()

    let ud = await provider.universeDomain()
    #expect(ud == defaultUniverseDomain)
  }

  @Test func credentialProviderWithTokenUri() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token-override")!
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "test-access-token",
      expiresIn: 3600,
      tokenType: "test-token-type"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

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

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      tokenUri: targetURL.absoluteString
    )

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    let headers = try await source.headers()
    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "test-token-type test-access-token" },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func credentialProviderWithScopes() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "test-access-token-with-scopes",
      expiresIn: 3600,
      tokenType: "test-token-type"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")

      // Read request body and verify scopes are space-separated
      guard let bodyData = request.bodyData else {
        fatalError("Expected HTTP body")
      }
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      do {
        let requestPayload = try decoder.decode(Oauth2RefreshRequest.self, from: bodyData)
        #expect(requestPayload.scopes == "scope1 scope2")
        #expect(requestPayload.clientId == "test-client-id")
        #expect(requestPayload.clientSecret == "test-client-secret")
        #expect(requestPayload.refreshToken == "test-refresh-token")
        #expect(requestPayload.grantType == "refresh_token")
      } catch {
        Issue.record("Failed to decode request body: \(error)")
      }

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: ["scope1", "scope2"],
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    let headers = try await source.headers()
    #expect(
      headers.contains {
        $0.0 == "Authorization" && $0.1 == "test-token-type test-access-token-with-scopes"
      },
      "Missing authorization header in \(headers)"
    )
  }

  @Test func credentialProviderRetryableError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 503,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      return (response, Data())
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    // Highly aggressive retry parameters so tests are fast
    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .seconds(0.01),
      multiplier: 1.5,
      maxDelay: .seconds(0.1)
    )

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: retryConfig,
      clock: TestClock()
    )

    await #expect(throws: AuthHTTPError.self) {
      _ = try await source.headers()
    }
  }

  @Test func tokenProviderNonretryableError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 401,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      return (response, Data())
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    await #expect(throws: AuthHTTPError.self) {
      _ = try await source.headers()
    }
  }

  @Test func tokenProviderMalformedResponseIsNonretryable() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let malformedPayload = "invalid-json"
    let encodedData = Data(malformedPayload.utf8)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    await #expect(throws: AuthHTTPError.self) {
      _ = try await source.headers()
    }
  }

  @Test func builderMalformedAuthorizedJsonNonretryable() async throws {
    let malformedJSON = """
      {
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "type": "authorized_user"
      }
      """
    let dataData = Data(malformedJSON.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    #expect(throws: DecodingError.self) {
      try decoder.decode(UserAccountData.self, from: dataData)
    }
  }

  /// Explicitly verifies that UserCredentials fully integrates with the thread-safe `TokenCache`
  /// and actively prevents "thundering herds". If the cache integration is faulty, multiple
  /// concurrent callers would each trigger identical HTTP requests to the token server.
  @Test func tokenHeadersCachingAndThunderingHerdPrevention() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "concurrent-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let requestCount = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")

      // Artificial small delay to let concurrent tasks spawn and queue up on the active refresh task
      Thread.sleep(forTimeInterval: 0.05)

      requestCount.increment()

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil as String?,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, encodedData)
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    // Spawn 10 concurrent headers() fetches
    let results = try await withThrowingTaskGroup(of: AuthHeaders.self) { group in
      for _ in 1...10 {
        group.addTask {
          try await source.headers()
        }
      }
      var allHeaders: [AuthHeaders] = []
      for try await h in group {
        allHeaders.append(h)
      }
      return allHeaders
    }

    #expect(results.count == 10)
    for headers in results {
      #expect(
        headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer concurrent-token" },
        "Missing authorization header in \(headers)"
      )
    }

    // Verify that only exactly ONE HTTP call was executed by the httpClient!
    let finalCount = requestCount.getCount()
    #expect(finalCount == 1)
  }

  @Test func testReproNonRetryableRetry() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      attempts.increment()
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 401,
        httpVersion: nil as String?,
        headerFields: nil as [String: String]?
      )!
      let errorPayload = Data("{\"error\": \"invalid_grant\"}".utf8)
      return (response, errorPayload)
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let retryConfig = RetryConfiguration(
      maxAttempts: 5,
      initialDelay: .seconds(0.01),
      multiplier: 1.5,
      maxDelay: .seconds(0.1)
    )

    let clock = TestClock()

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: retryConfig,
      clock: clock
    )

    await #expect(throws: AuthHTTPError.self) {
      _ = try await source.headers()
    }

    // Give the background task a moment to run and either sleep or terminate.
    try? await Task.sleep(for: .milliseconds(100))

    // Real-time sleeps are necessary because background refresh loops and URLSession
    // mock protocols execute asynchronously across thread boundaries.
    if clock.hasSleepers {
      clock.advance(by: .seconds(11))
      // Wait for the async retry attempt to complete
      try? await Task.sleep(for: .milliseconds(100))
    }

    #expect(attempts.getCount() == 1)
  }

  @Test func initializerRejectsNonDefaultUniverse() async throws {
    let mockData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token"
    )

    #expect {
      try UserCredentials(
        user: mockData,
        universeDomain: "custom.com",
        httpClient: AuthHTTPClient(session: self.mockSession),
        retryConfiguration: .defaultConfiguration,
        clock: TestClock()
      )
    } throws: { error in
      guard let credError = error as? CredentialsError else { return false }
      if case let .notSupported(message) = credError {
        return message.contains("custom universes: custom.com")
      }
      return false
    }
  }

  @Test func testRetryOnTransientNetworkError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let attempts = CallCounter()
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "recovered-timeout-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    MockURLProtocol.requestHandler = { (request: URLRequest) in
      attempts.increment()
      if attempts.getCount() == 1 {
        throw URLError(.timedOut)
      } else {
        let response = HTTPURLResponse(
          url: targetURL,
          statusCode: 200,
          httpVersion: nil as String?,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, encodedData)
      }
    }

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let retryConfig = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .seconds(0.01),
      multiplier: 1.5,
      maxDelay: .seconds(0.1)
    )

    let clock = TestClock()

    let source = try UserCredentials(
      user: data,
      scopes: nil,
      httpClient: AuthHTTPClient(session: self.mockSession),
      retryConfiguration: retryConfig,
      clock: clock
    )

    // Give the background task a moment to run and fail (1st attempt)
    try? await Task.sleep(for: .milliseconds(100))

    // If it is retryable, it should have registered a sleeper.
    #expect(clock.hasSleepers == true)

    if clock.hasSleepers {
      // Advance clock to trigger retry (2nd attempt, should succeed)
      clock.advance(by: .seconds(11))
      // Wait for the async retry attempt to complete and update cache
      try? await Task.sleep(for: .milliseconds(100))
    }

    // Now headers() should succeed using the cached token
    let headers = try await source.headers()
    #expect(
      headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer recovered-timeout-token" })
    #expect(attempts.getCount() == 2)
  }
}

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.requestHandler else {
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
