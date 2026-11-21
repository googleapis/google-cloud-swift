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

@Suite struct UserCredentialsTest {
  /// Verifies that initializing `UserCredentials` does not eagerly make a token refresh
  /// network request before `headers()` is called.
  @Test func userProviderInitializationDoesNotMakeNetworkRequests() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let mock = MockHTTPClient([])

    let mockData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token",
      tokenUri: targetURL.absoluteString,
      quotaProjectId: "mock-project"
    )

    let provider = try UserCredentials(
      user: mockData,
      universeDomain: defaultUniverseDomain,
      httpClient: AuthHTTPClient(mock: mock)
    )

    await Task.yield()
    // `MockHTTPClient.execute` records the per-request `timeout` argument on every call,
    // so an empty `recordedTimeouts` array verifies zero HTTP requests were issued.
    #expect(mock.recordedTimeouts.isEmpty)
    _ = provider
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

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      tokenUri: targetURL.absoluteString
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers = try await source.headers()
    #expect(
      headers["Authorization"] == "test-token-type test-access-token",
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

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        // Read request body and verify scopes are space-separated
        guard let bodyData = try await request.body?.collect(upTo: 1024 * 1024) else {
          fatalError("Expected HTTP body")
        }

        // Verify outgoing request body contains snake_case keys as required by:
        // - RFC 6749 Section 6 (grant_type, refresh_token): https://datatracker.ietf.org/doc/html/rfc6749#section-6
        // - RFC 6749 Section 2.3.1 (client_id, client_secret): https://datatracker.ietf.org/doc/html/rfc6749#section-2.3.1
        // - Google Identity OAuth 2.0: https://developers.google.com/identity/protocols/oauth2/web-server#offline
        if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
          #expect(jsonObject["grant_type"] as? String == "refresh_token")
          #expect(jsonObject["client_id"] as? String == "test-client-id")
          #expect(jsonObject["client_secret"] as? String == "test-client-secret")
          #expect(jsonObject["refresh_token"] as? String == "test-refresh-token")
          #expect(jsonObject["scopes"] as? String == "scope1 scope2")
          #expect(jsonObject["grantType"] == nil)
          #expect(jsonObject["clientId"] == nil)
          #expect(jsonObject["clientSecret"] == nil)
          #expect(jsonObject["refreshToken"] == nil)
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

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: ["scope1", "scope2"],
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers = try await source.headers()
    #expect(
      headers["Authorization"] == "test-token-type test-access-token-with-scopes",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func credentialProviderOmitsEmptyScopes() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "test-access-token-without-scopes",
      expiresIn: 3600,
      tokenType: "test-token-type"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        guard let bodyData = try await request.body?.collect(upTo: 1024 * 1024) else {
          fatalError("Expected HTTP body")
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
          #expect(jsonObject["grant_type"] as? String == "refresh_token")
          #expect(jsonObject["client_id"] as? String == "test-client-id")
          #expect(jsonObject["client_secret"] as? String == "test-client-secret")
          #expect(jsonObject["refresh_token"] as? String == "test-refresh-token")
          #expect(jsonObject["scopes"] == nil)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
          let requestPayload = try decoder.decode(Oauth2RefreshRequest.self, from: bodyData)
          #expect(requestPayload.scopes == nil)
          #expect(requestPayload.clientId == "test-client-id")
          #expect(requestPayload.clientSecret == "test-client-secret")
          #expect(requestPayload.refreshToken == "test-refresh-token")
          #expect(requestPayload.grantType == "refresh_token")
        } catch {
          Issue.record("Failed to decode request body: \(error)")
        }

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      scopes: [],
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers = try await source.headers()
    #expect(
      headers["Authorization"] == "test-token-type test-access-token-without-scopes",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func credentialProviderRetryableError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        return HTTPClientResponse(
          version: .http2,
          status: .serviceUnavailable,
        )
      }
    ])

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
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig
    )

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error))")
      return
    }
    #expect(underlyingError is AuthHTTPError)
  }

  @Test func tokenProviderNonretryableError() async throws {
    let targetURL = URL(string: "https://oauth2.googleapis.com/token")!

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        return HTTPClientResponse(
          version: .http2,
          status: .unauthorized,
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error))")
      return
    }
    #expect(underlyingError is AuthHTTPError)
  }

  @Test func tokenProviderMalformedResponseIsNonretryable() async throws {
    let attempts = CallCounter()
    let malformedPayload = "invalid-json"
    let encodedData = Data(malformedPayload.utf8)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let retryConfig = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError1) = error1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is AuthHTTPError)
    #expect(attempts.getCount() == 1)

    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError2) = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(underlyingError2 is AuthHTTPError)
    #expect(attempts.getCount() == 1)
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

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        // Artificial small delay to let concurrent tasks spawn and queue up on the active refresh task
        try await Task.sleep(until: ContinuousClock.Instant.now + .milliseconds(50))

        requestCount.increment()

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock)
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
        headers["Authorization"] == "Bearer concurrent-token",
        "Missing authorization header in \(headers)"
      )
    }

    // Verify that only exactly ONE HTTP call was executed by the httpClient!
    let finalCount = requestCount.getCount()
    #expect(finalCount == 1)
  }

  /// Verifies that a non-retryable 401 `invalid_grant` response neither retries inside
  /// `RetryEngine` nor triggers a new HTTP fetch on subsequent `headers()` calls (proving
  /// `UserCredentials` wires `isRetryable: AuthHTTPError.isRetryable` into `TokenCache`).
  @Test func testReproNonRetryableRetry() async throws {
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        attempts.increment()
        let errorPayload = Data("{\"error\": \"invalid_grant\"}".utf8)
        return HTTPClientResponse(
          version: .http2,
          status: .unauthorized,
          body: .bytes(.init(data: errorPayload)),
        )
      }
    ])

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

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError1) = error1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is AuthHTTPError)
    #expect(attempts.getCount() == 1)
    #expect(mock.recordedTimeouts.count == 1)

    // Calling `headers()` a second time verifies `TokenCache` recorded the 401 as a permanent
    // error via `AuthHTTPError.isRetryable` rather than defaulting to `{ _ in true }` and
    // issuing another request to `MockHTTPClient`.
    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await source.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError2) = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(underlyingError2 is AuthHTTPError)
    #expect(attempts.getCount() == 1)
    #expect(mock.recordedTimeouts.count == 1)
  }

  @Test func initializerRejectsNonDefaultUniverse() async throws {
    let mockData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token"
    )
    let mock = MockHTTPClient([])

    #expect {
      try UserCredentials(
        user: mockData,
        universeDomain: "custom.com",
        httpClient: AuthHTTPClient(mock: mock)
      )
    } throws: { error in
      guard let credError = error as? CredentialsError else { return false }
      if case let .notSupported(message) = credError {
        return message.contains("default (googleapis.com) universe: custom.com")
      }
      return false
    }
  }

  @Test func testRetryOnTransientNetworkError() async throws {
    let attempts = CallCounter()
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "recovered-timeout-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        attempts.increment()
        throw URLError(.timedOut)
      },
      { (request: HTTPClientRequest) in
        attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      },
    ])

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

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig
    )

    // Calling headers() triggers the lazy token fetch, which retries the transient timeout and succeeds
    let headers = try await source.headers()
    #expect(headers["Authorization"] == "Bearer recovered-timeout-token")
    #expect(attempts.getCount() == 2)
  }

  @Test func headersIncludesQuotaProjectFromUserAccountData() async throws {
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "mock-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      quotaProjectId: "user-json-quota-proj"
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers = try await source.headers()
    #expect(headers["x-goog-user-project"] == "user-json-quota-proj")
  }

  @Test func headersQuotaProjectParameterOverridesUserAccountData() async throws {
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "mock-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      quotaProjectId: "user-json-quota-proj"
    )

    let source = try UserCredentials(
      user: data,
      quotaProjectID: "override-quota-proj",
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers = try await source.headers()
    #expect(headers.values(for: "x-goog-user-project") == ["override-quota-proj"])
  }

  @Test func headersNormalizesEmptyQuotaProjectStrings() async throws {
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "mock-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let makeMockClient = {
      AuthHTTPClient(
        mock: MockHTTPClient([
          { _ in
            HTTPClientResponse(
              version: .http2,
              status: .ok,
              headers: .init([("Content-Type", "application/json")]),
              body: .bytes(.init(data: encodedData))
            )
          }
        ])
      )
    }

    let emptyJSONData = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      quotaProjectId: ""
    )

    let credsFromEmptyJSON = try UserCredentials(user: emptyJSONData, httpClient: makeMockClient())
    #expect(credsFromEmptyJSON.quotaProjectID == nil)
    let headersFromEmptyJSON = try await credsFromEmptyJSON.headers()
    #expect(headersFromEmptyJSON["x-goog-user-project"] == nil)

    let credsWithBothEmpty = try UserCredentials(
      user: emptyJSONData, quotaProjectID: "", httpClient: makeMockClient())
    #expect(credsWithBothEmpty.quotaProjectID == nil)
    let headersWithBothEmpty = try await credsWithBothEmpty.headers()
    #expect(headersWithBothEmpty["x-goog-user-project"] == nil)

    let credsOverrideOverEmptyJSON = try UserCredentials(
      user: emptyJSONData, quotaProjectID: "override-proj", httpClient: makeMockClient())
    let headersOverrideOverEmptyJSON = try await credsOverrideOverEmptyJSON.headers()
    #expect(headersOverrideOverEmptyJSON.values(for: "x-goog-user-project") == ["override-proj"])

    let nonEmptyJSONData = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      quotaProjectId: "user-json-quota-proj"
    )
    let credsEmptyParamFallsBackToJSON = try UserCredentials(
      user: nonEmptyJSONData, quotaProjectID: "", httpClient: makeMockClient())
    let headersEmptyParamFallsBackToJSON = try await credsEmptyParamFallsBackToJSON.headers()
    #expect(
      headersEmptyParamFallsBackToJSON.values(for: "x-goog-user-project") == [
        "user-json-quota-proj"
      ]
    )

    let rawEmptyJSONKey = Data(
      """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "quota_project_id": ""
      }
      """.utf8)
    let parsedFromRawEmptyJSON = try UserCredentials(keyJSON: rawEmptyJSONKey, quotaProjectID: "")
    #expect(parsedFromRawEmptyJSON.quotaProjectID == nil)
  }

  @Test func tokenProviderSurfacesOAuthErrorBodyInCredentialsError() async throws {
    let oauthErrorJSON =
      #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#
    let bodyData = Data(oauthErrorJSON.utf8)

    let mock = MockHTTPClient([
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: .badRequest,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: bodyData))
        )
      }
    ])

    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "expired-refresh-token"
    )

    let source = try UserCredentials(
      user: data,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let error = try #require(
      await #expect(throws: CredentialsError.self) {
        _ = try await source.headers()
      }
    )
    let anyError: any Error = error

    let described = String(describing: anyError)
    let reflected = String(reflecting: anyError)

    #expect(described.contains("HTTP status 400"))
    #expect(described.contains("invalid_grant"))
    #expect(described.contains("Token has been expired or revoked."))
    #expect(!described.contains("bytes"))

    #expect(reflected.contains("CredentialsError.cannotFetchToken"))
    #expect(reflected.contains("statusCode: 400"))
    #expect(reflected.contains("invalid_grant"))
    #expect(reflected.contains("Token has been expired or revoked."))
    #expect(!reflected.contains("bytes"))
  }

  @Test func initializerValidatesUserAccountDataUniverseDomain() async throws {
    let mock = MockHTTPClient([])

    let defaultUniverseData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token",
      universeDomain: "googleapis.com"
    )
    let creds = try UserCredentials(
      user: defaultUniverseData,
      httpClient: AuthHTTPClient(mock: mock)
    )
    #expect(try await creds.universeDomain() == "googleapis.com")

    let emptyUniverseData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token",
      universeDomain: ""
    )
    let credsWithEmptyUniverse = try UserCredentials(
      user: emptyUniverseData,
      universeDomain: "",
      httpClient: AuthHTTPClient(mock: mock)
    )
    #expect(try await credsWithEmptyUniverse.universeDomain() == "googleapis.com")

    let customUniverseData = UserAccountData(
      type: "authorized_user",
      clientId: "mock-id",
      clientSecret: "mock-secret",
      refreshToken: "mock-token",
      universeDomain: "custom.com"
    )
    #expect {
      _ = try UserCredentials(
        user: customUniverseData,
        httpClient: AuthHTTPClient(mock: mock)
      )
    } throws: { error in
      guard case let CredentialsError.notSupported(message) = error else { return false }
      return message.contains("custom.com")
    }
  }

  @Test(
    arguments: [
      (
        UserAccountData(
          type: "authorized_user",
          clientId: "test-client-id.apps.googleusercontent.com",
          clientSecret: "super-secret-oauth-client-secret",
          refreshToken: "1//super-secret-oauth-refresh-token",
          tokenUri: "https://oauth2.googleapis.com/token",
          quotaProjectId: "my-quota-project",
          universeDomain: "googleapis.com"
        ),
        "UserAccountData(type: \"authorized_user\", clientId: \"test-client-id.apps.googleusercontent.com\", clientSecret: \"[redacted]\", refreshToken: \"[redacted]\", tokenUri: \"https://oauth2.googleapis.com/token\", quotaProjectId: \"my-quota-project\", universeDomain: \"googleapis.com\")"
      ),
      (
        UserAccountData(
          type: "authorized_user",
          clientId: "minimal-client-id",
          clientSecret: "minimal-client-secret",
          refreshToken: "minimal-refresh-token"
        ),
        "UserAccountData(type: \"authorized_user\", clientId: \"minimal-client-id\", clientSecret: \"[redacted]\", refreshToken: \"[redacted]\", tokenUri: nil, quotaProjectId: nil, universeDomain: nil)"
      ),
    ]
  )
  func userAccountDataDescriptionsRedactSecrets(
    data: UserAccountData,
    expected: String
  ) {
    #expect(String(describing: data) == expected)
    #expect(String(reflecting: data) == expected)
  }

  @Test func userCredentialsDescriptionsRedactSecrets() throws {
    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id.apps.googleusercontent.com",
      clientSecret: "super-secret-oauth-client-secret",
      refreshToken: "1//super-secret-oauth-refresh-token",
      tokenUri: "https://oauth2.googleapis.com/token",
      quotaProjectId: "my-quota-project",
      universeDomain: "googleapis.com"
    )
    let userCreds = try UserCredentials(
      user: data,
      scopes: ["scope-a"],
      httpClient: AuthHTTPClient(mock: MockHTTPClient([]))
    )

    for output in [String(describing: userCreds), String(reflecting: userCreds)] {
      #expect(!output.contains("super-secret-oauth-client-secret"))
      #expect(!output.contains("1//super-secret-oauth-refresh-token"))
      #expect(output.contains("[redacted]"))
      #expect(output.contains("test-client-id.apps.googleusercontent.com"))
      #expect(output.contains("my-quota-project"))
      #expect(output.contains("googleapis.com"))
      #expect(output.contains("scope-a"))
    }
  }

  @Test func publicUserCredentialsDescriptionsRedactSecrets() throws {
    let keyJSON = Data(
      """
      {
        "type": "authorized_user",
        "client_id": "public-creds-client-id",
        "client_secret": "public-creds-client-secret",
        "refresh_token": "public-creds-refresh-token",
        "quota_project_id": "public-creds-quota-proj",
        "universe_domain": "googleapis.com"
      }
      """.utf8
    )
    let credentials = try Credentials(configuration: .user(UserConfig(keyJSON: keyJSON)))

    for output in [String(describing: credentials), String(reflecting: credentials)] {
      #expect(!output.contains("public-creds-client-secret"))
      #expect(!output.contains("public-creds-refresh-token"))
      #expect(output.contains("[redacted]"))
      #expect(output.contains("public-creds-client-id"))
      #expect(output.contains("public-creds-quota-proj"))
      #expect(output.contains("googleapis.com"))
    }
  }

  @Test(
    arguments: [
      nil,
      "https://oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com:443/token",
      "HTTPS://OAUTH2.GOOGLEAPIS.COM/token",
      "https://oauth2.googleapis.com/token-override",
      "https://oauth2.googleapis.com/a..b",
      "https://oauth2.googleapis.com/",
    ] as [String?]
  )
  func initializerAcceptsValidTokenURIs(tokenURI: String?) throws {
    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      tokenUri: tokenURI
    )
    let mock = MockHTTPClient([])
    let creds = try UserCredentials(user: data, httpClient: AuthHTTPClient(mock: mock))
    #expect(
      creds.provider.tokenURL.absoluteString == (tokenURI ?? "https://oauth2.googleapis.com/token"))
    #expect(mock.recordedTimeouts.isEmpty)

    let payload: [String: String] =
      if let tokenURI {
        [
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token",
          "token_uri": tokenURI,
        ]
      } else {
        [
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token",
        ]
      }
    let keyJSON = try JSONEncoder().encode(payload)
    let jsonCreds = try UserCredentials(keyJSON: keyJSON)
    #expect(
      jsonCreds.provider.tokenURL.absoluteString
        == (tokenURI ?? "https://oauth2.googleapis.com/token")
    )
  }

  @Test(
    arguments: [
      "http://oauth2.googleapis.com/token",
      "https://other.example.com/token",
      "https://oauth2.googleapis.com.other.example/token",
      "https://other-oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com./token",
      "https://169.254.169.254/token",
      "https://127.0.0.1/token",
      "unix:///tmp/sock",
      "http+unix://%2Ftmp%2Fsock/token",
      "https://oauth2.googleapis.com:8443/token",
      "https://user:pass@oauth2.googleapis.com/token",
      "https://user@oauth2.googleapis.com/token",
      "https://@oauth2.googleapis.com/token",
      "https://:pass@oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com/token?foo=bar",
      "https://oauth2.googleapis.com/token?",
      "https://oauth2.googleapis.com/token#frag",
      "https://oauth2.googleapis.com/token#",
      "https://oauth2.googleapis.com/./token",
      "https://oauth2.googleapis.com/%2e/token",
      "https://oauth2.googleapis.com/%2E/token",
      "https://oauth2.googleapis.com/token/.",
      "https://oauth2.googleapis.com/.",
      "https://oauth2.googleapis.com/%2e",
      "https://oauth2.googleapis.com/v1/../token",
      "https://oauth2.googleapis.com/%2e%2e/token",
      "https://oauth2.googleapis.com/v1/%2f..%2f/token",
      "https://oauth2.googleapis.com/v1/..%2ftoken",
      "https://oauth2.googleapis.com/token/..",
      "https://oauth2.googleapis.com/v1/\\token",
      "https://oauth2.googleapis.com/%5ctoken",
      "https://oauth2.googleapis.com/v1/%5c../token",
      "https://oauth2.googleapis.com/token%2fextra",
      "https://oauth2.googleapis.com/token%20",
      "https://oauth2.googleapis.com/token%0a",
      "https://oauth2.googleapis.com/token%00",
      "https://oauth2%2egoogleapis.com/token",
      "https://oauth2.googleapis.com",
      " https://oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com/token ",
      "   ",
      "\t\n",
      "",
      "not-a-valid-url",
    ]
  )
  func initializerRejectsInvalidTokenURIs(tokenURI: String) throws {
    let data = UserAccountData(
      type: "authorized_user",
      clientId: "test-client-id",
      clientSecret: "test-client-secret",
      refreshToken: "test-refresh-token",
      tokenUri: tokenURI
    )
    let mock = MockHTTPClient([])

    let error = #expect(throws: CredentialsError.self) {
      _ = try UserCredentials(user: data, httpClient: AuthHTTPClient(mock: mock))
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(mock.recordedTimeouts.isEmpty)

    let payload: [String: String] = [
      "type": "authorized_user",
      "client_id": "test-client-id",
      "client_secret": "test-client-secret",
      "refresh_token": "test-refresh-token",
      "token_uri": tokenURI,
    ]
    let keyJSON = try JSONEncoder().encode(payload)
    let jsonError = #expect(throws: CredentialsError.self) {
      _ = try UserCredentials(keyJSON: keyJSON)
    }
    guard case .parseError = jsonError else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: jsonError))")
      return
    }
  }
}
