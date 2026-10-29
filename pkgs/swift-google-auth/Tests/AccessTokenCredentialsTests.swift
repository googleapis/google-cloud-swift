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
import GoogleWKT
import NIOFoundationCompat
import NIOHTTP1
import Testing

@testable import GoogleAuth

private actor MockCustomAccessTokenProvider: AccessTokenProvider {
  private var callCount = 0
  private var nextToken: AccessToken?
  private var nextError: (any Error)?

  init(token: AccessToken? = nil, error: (any Error)? = nil) {
    self.nextToken = token
    self.nextError = error
  }

  func configure(token: AccessToken?, error: (any Error)? = nil) {
    self.nextToken = token
    self.nextError = error
  }

  func accessToken() async throws -> AccessToken {
    self.callCount += 1
    if let error = self.nextError {
      throw error
    }
    guard let token = self.nextToken else {
      throw URLError(.unknown)
    }
    return token
  }

  var count: Int {
    self.callCount
  }
}

private actor DelayedCustomAccessTokenProvider: AccessTokenProvider {
  private var callCount = 0
  private let token: AccessToken

  init(token: AccessToken) {
    self.token = token
  }

  func accessToken() async throws -> AccessToken {
    self.callCount += 1
    try await Task.sleep(for: .milliseconds(50))
    return self.token
  }

  var count: Int {
    self.callCount
  }
}

@Suite struct AccessTokenCredentialsTests {
  // MARK: - AccessToken Value Type Tests

  @Test func accessTokenPropertiesAndEquality() {
    let expiry = Date(timeIntervalSince1970: 1_700_000_000)
    let tokenWithExpiry = AccessToken(token: "mock-token.test-token", expirationDate: expiry)
    #expect(tokenWithExpiry.token == "mock-token.test-token")
    #expect(tokenWithExpiry.expirationDate == expiry)

    let tokenWithoutExpiry = AccessToken(token: "mock-token.test-token")
    #expect(tokenWithoutExpiry.token == "mock-token.test-token")
    #expect(tokenWithoutExpiry.expirationDate == nil)

    #expect(tokenWithExpiry == AccessToken(token: "mock-token.test-token", expirationDate: expiry))
    #expect(tokenWithExpiry != tokenWithoutExpiry)

    var set = Set<AccessToken>()
    set.insert(tokenWithExpiry)
    set.insert(tokenWithoutExpiry)
    #expect(set.count == 2)
  }

  @Test func accessTokenDebugAndStringDescriptionsRedactToken() {
    let expiry = Date(timeIntervalSince1970: 1_700_000_000)
    let token = AccessToken(token: "mock-token.super-secret-access-token", expirationDate: expiry)

    let debugDesc = String(reflecting: token)
    #expect(!debugDesc.contains("mock-token.super-secret-access-token"))
    #expect(debugDesc.contains("[redacted]"))

    let stringDesc = String(describing: token)
    #expect(!stringDesc.contains("mock-token.super-secret-access-token"))
    #expect(stringDesc.contains("[redacted]"))

    let internalToken = Token(
      accessToken: "mock-token.internal-secret",
      tokenType: "Bearer",
      expirationDate: expiry
    )
    #expect(!String(reflecting: internalToken).contains("mock-token.internal-secret"))
    #expect(String(reflecting: internalToken).contains("[redacted]"))
    #expect(!String(describing: internalToken).contains("mock-token.internal-secret"))
    #expect(String(describing: internalToken).contains("[redacted]"))
  }

  // MARK: - Static AccessToken Configuration Tests

  @Test func staticAccessTokenWithoutExpiration() async throws {
    let credentials = try Credentials(
      configuration: .accessToken("mock-token.static-token")
    )

    let token = try await credentials.accessToken()
    #expect(token.token == "mock-token.static-token")
    #expect(token.expirationDate == nil)

    let headers = try await credentials.headers()
    #expect(headers == [("Authorization", "Bearer mock-token.static-token")])
  }

  @Test func staticAccessTokenStructWithExpirationAndQuotaProject() async throws {
    let futureExpiry = Date().addingTimeInterval(3600)
    let expectedToken = AccessToken(token: "mock-token.struct-token", expirationDate: futureExpiry)
    let credentials = try Credentials(
      configuration: .accessToken(
        expectedToken,
        quotaProjectID: "my-quota-project",
        universeDomain: "custom.universe.com"
      )
    )

    let token = try await credentials.accessToken()
    #expect(token == expectedToken)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.struct-token"),
        ("x-goog-user-project", "my-quota-project"),
      ]
    )
  }

  @Test func staticAccessTokenStringOverloadWithExpirationAndQuotaProject() async throws {
    let futureExpiry = Date().addingTimeInterval(3600)
    let credentials = try Credentials(
      configuration: .accessToken(
        "mock-token.overload-token",
        expirationDate: futureExpiry,
        quotaProjectID: "my-quota-project",
        universeDomain: "custom.universe.com"
      )
    )

    let token = try await credentials.accessToken()
    #expect(token.token == "mock-token.overload-token")
    #expect(token.expirationDate == futureExpiry)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.overload-token"),
        ("x-goog-user-project", "my-quota-project"),
      ]
    )
  }

  @Test func staticAccessTokenThrowsWhenExpired() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let timeSource = MockTimeSource(currentDate: now)
    let expiry = now.addingTimeInterval(60)

    let staticCreds = StaticAccessTokenCredentials(
      token: AccessToken(token: "mock-token.expiring-token", expirationDate: expiry),
      quotaProjectID: "proj-1",
      timeSource: timeSource
    )

    // Valid before expiration
    let validToken = try await staticCreds.accessToken()
    #expect(validToken.token == "mock-token.expiring-token")
    let validHeaders = try await staticCreds.headers()
    #expect(validHeaders["Authorization"] == "Bearer mock-token.expiring-token")

    // Advance clock to exact expiration time
    timeSource.advance(by: 60)

    let tokenError = await #expect(throws: CredentialsError.self) {
      _ = try await staticCreds.accessToken()
    }
    if case let .cannotFetchToken(message, _) = tokenError {
      #expect(message.contains("expired"))
    } else {
      Issue.record(
        "Expected CredentialsError.cannotFetchToken, got \(String(describing: tokenError))")
    }

    let headersError = await #expect(throws: CredentialsError.self) {
      _ = try await staticCreds.headers()
    }
    if case let .cannotFetchToken(message, _) = headersError {
      #expect(message.contains("expired"))
    } else {
      Issue.record(
        "Expected CredentialsError.cannotFetchToken, got \(String(describing: headersError))")
    }
  }

  @Test func staticAccessTokenDebugDescriptionRedactsSecret() {
    let staticCreds = StaticAccessTokenCredentials(
      token: AccessToken(token: "mock-token.secret-static-value"),
      quotaProjectID: "quota-123"
    )
    let debugDesc = String(reflecting: staticCreds)
    #expect(!debugDesc.contains("mock-token.secret-static-value"))
    #expect(debugDesc.contains("[redacted]"))
    #expect(debugDesc.contains("quota-123"))
  }

  // MARK: - Custom AccessTokenProvider Tests

  @Test func customAccessTokenProviderReturnsTokenAndHeaders() async throws {
    let expiry = Date().addingTimeInterval(3600)
    let provider = MockCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.custom-provider-token", expirationDate: expiry)
    )

    let credentials = try Credentials(
      configuration: .accessTokenProvider(
        provider,
        quotaProjectID: "custom-quota-project",
        universeDomain: "custom.universe.com"
      )
    )

    let token = try await credentials.accessToken()
    #expect(token.token == "mock-token.custom-provider-token")
    #expect(token.expirationDate == expiry)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.custom-provider-token"),
        ("x-goog-user-project", "custom-quota-project"),
      ]
    )

    // Subsequent calls return cached token without hitting provider again
    let token2 = try await credentials.accessToken()
    #expect(token2 == token)
    #expect(await provider.count == 1)
  }

  @Test func customAccessTokenProviderNonExpiringTokenTerminatesBackgroundRefresh() async throws {
    let provider = MockCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.non-expiring-custom-token", expirationDate: nil)
    )
    let clock = TestClock()
    let timeSource = MockTimeSource(currentDate: Date())

    let cache = TokenCache(
      provider: CustomAccessTokenProviderAdapter(provider: provider),
      clock: clock,
      timeSource: timeSource,
      isRetryable: AuthHTTPError.isRetryable
    )

    let token1 = try await cache.token().asAccessToken
    #expect(token1.token == "mock-token.non-expiring-custom-token")
    #expect(token1.expirationDate == nil)

    // Advance time significantly; non-expiring token should remain valid and never re-fetch
    timeSource.advance(by: 86_400)
    clock.advance(by: .seconds(86_400))

    let token2 = try await cache.token().asAccessToken
    #expect(token2.token == "mock-token.non-expiring-custom-token")
    #expect(await provider.count == 1)
    #expect(!clock.hasSleepers)
  }

  @Test func customAccessTokenProviderProactiveRefreshAndSingleflight() async throws {
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)
    let clock = TestClock()

    let initialExpiry = now.addingTimeInterval(10)
    let provider = MockCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.initial", expirationDate: initialExpiry)
    )

    let cache = TokenCache(
      provider: CustomAccessTokenProviderAdapter(provider: provider),
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      isRetryable: AuthHTTPError.isRetryable
    )

    let firstToken = try await cache.token().asAccessToken
    #expect(firstToken.token == "mock-token.initial")
    #expect(await provider.count == 1)
    await clock.sleeperWaiting()

    let refreshedExpiry = now.addingTimeInterval(3600)
    await provider.configure(
      token: AccessToken(token: "mock-token.refreshed", expirationDate: refreshedExpiry)
    )

    // Advance into staleness window (10s - 2s = 8s)
    timeSource.advance(by: 8.5)
    clock.advance(by: .seconds(8.5))

    await clock.sleeperWaiting()
    let secondToken = try await cache.token().asAccessToken
    #expect(secondToken.token == "mock-token.refreshed")
    #expect(secondToken.expirationDate == refreshedExpiry)
    #expect(await provider.count == 2)
  }

  @Test func customAccessTokenProviderSingleflightCoalescesConcurrentRequests() async throws {
    let expiry = Date().addingTimeInterval(3600)
    let provider = DelayedCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.coalesced", expirationDate: expiry)
    )
    let credentials = try Credentials(configuration: .accessTokenProvider(provider))

    let tokens = try await withThrowingTaskGroup(of: AccessToken.self) { group in
      for _ in 1...8 {
        group.addTask {
          try await credentials.accessToken()
        }
      }
      var results: [AccessToken] = []
      for try await t in group {
        results.append(t)
      }
      return results
    }

    #expect(tokens.count == 8)
    for token in tokens {
      #expect(token.token == "mock-token.coalesced")
    }
    #expect(await provider.count == 1)
  }

  @Test func customAccessTokenProviderWrapsThrownErrorsInCannotFetchToken() async throws {
    struct CustomFailure: Error, Equatable {}
    let provider = MockCustomAccessTokenProvider(token: nil, error: CustomFailure())
    let credentials = try Credentials(configuration: .accessTokenProvider(provider))

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error))")
      return
    }
    #expect(underlyingError is CustomFailure)
  }

  @Test func customAccessTokenProviderPermanentErrorStopsBackgroundRetries() async throws {
    let provider = MockCustomAccessTokenProvider(
      token: nil,
      error: CredentialsError.parseError("invalid configuration")
    )
    let clock = TestClock()
    let timeSource = MockTimeSource(currentDate: Date())

    let cache = TokenCache(
      provider: CustomAccessTokenProviderAdapter(provider: provider),
      clock: clock,
      timeSource: timeSource,
      isRetryable: AuthHTTPError.isRetryable
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await cache.token().asAccessToken
    }
    guard case let .cannotFetchToken(_, underlyingError1) = error1,
      case .parseError = underlyingError1 as? CredentialsError
    else {
      Issue.record("Expected permanent parseError wrapped in cannotFetchToken, got \(error1)")
      return
    }
    #expect(await provider.count == 1)

    // Subsequent call must throw cached permanent error without re-invoking provider
    _ = await #expect(throws: CredentialsError.self) {
      _ = try await cache.token().asAccessToken
    }
    #expect(await provider.count == 1)
    #expect(!clock.hasSleepers)
  }

  @Test func customAccessTokenProviderDoesNotDoubleWrapCannotFetchToken() async throws {
    struct InnerError: Error {}
    let originalError = CredentialsError.cannotFetchToken(
      message: "custom message",
      underlyingError: InnerError()
    )
    let provider = MockCustomAccessTokenProvider(token: nil, error: originalError)
    let credentials = try Credentials(configuration: .accessTokenProvider(provider))

    let thrownError = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case let .cannotFetchToken(message, underlyingError) = thrownError else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(thrownError)")
      return
    }
    #expect(message == "custom message")
    #expect(underlyingError is InnerError)
  }

  @Test func customAccessTokenProviderPropagatesCancellationErrorDirectly() async throws {
    let clock = TestClock()
    let timeSource = MockTimeSource(currentDate: Date())
    let provider = MockCustomAccessTokenProvider(token: nil, error: CancellationError())
    let cache = TokenCache(
      provider: CustomAccessTokenProviderAdapter(provider: provider),
      clock: clock,
      timeSource: timeSource,
      isRetryable: AuthHTTPError.isRetryable
    )

    // First call fails with CancellationError from the provider
    await #expect(throws: CancellationError.self) {
      _ = try await cache.token().asAccessToken
    }
    #expect(await provider.count == 1)

    // Subsequent call must not be poisoned by permanentError or a stale activeRefreshTask
    let expectedToken = AccessToken(
      token: "mock-token.recovered-after-cancel",
      expirationDate: timeSource.now.addingTimeInterval(3600)
    )
    await provider.configure(token: expectedToken, error: nil)

    let recovered = try await cache.token().asAccessToken
    #expect(recovered == expectedToken)
    #expect(await provider.count == 2)
  }

  // MARK: - Credentials.accessToken() Across Built-in Providers

  @Test func anonymousCredentialsAccessTokenThrowsNotSupported() async throws {
    let credentials = try Credentials(configuration: .anonymous)
    let error = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case .notSupported = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
  }

  @Test func apiKeyCredentialsAccessTokenThrowsNotSupported() async throws {
    let credentials = try Credentials(configuration: .apiKey("my-api-key"))
    let error = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case .notSupported = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
  }

  @Test func userCredentialsAccessTokenExtractsRawTokenAndExpiry() async throws {
    let responsePayload = Oauth2RefreshResponse(
      accessToken: "mock-token.user-access-token",
      expiresIn: 3600,
      tokenType: "Bearer"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { _ in
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
      refreshToken: "test-refresh-token"
    )

    let userCreds = try UserCredentialsGeneric(
      user: data,
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: .defaultConfiguration,
      clock: TestClock()
    )

    let accessToken = try await userCreds.accessToken()
    #expect(accessToken.token == "mock-token.user-access-token")
    #expect(accessToken.expirationDate != nil)
  }

  @Test func mdsCredentialsAccessTokenExtractsRawTokenAndExpiry() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(
      MockResponse(accessToken: "mock-token.mds-access-token", expiresIn: 3600, tokenType: "Bearer")
    )

    let mock = MockHTTPClient([
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let mdsCreds = MDSCredentials(client: AuthHTTPClient(mock: mock), environment: [:])
    let accessToken = try await mdsCreds.accessToken()
    #expect(accessToken.token == "mock-token.mds-access-token")
    #expect(accessToken.expirationDate != nil)
  }

  @Test func externalAccountCredentialsAccessTokenExtractsRawTokenAndExpiry() async throws {
    struct StaticSubjectTokenProvider: SubjectTokenProvider {
      func subjectToken() async throws -> String { "subj-token" }
    }

    let expectedResponse = TokenResponse(
      accessToken: "mock-token.external-access-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let extCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: StaticSubjectTokenProvider()),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let accessToken = try await extCreds.accessToken()
    #expect(accessToken.token == "mock-token.external-access-token")
    #expect(accessToken.expirationDate != nil)
  }

  @Test func impersonatedCredentialsAccessTokenExtractsRawTokenAndExpiry() async throws {
    let sourceCreds = StaticAccessTokenCredentials(
      token: AccessToken(token: "mock-token.source-token")
    )
    let expectedExpiry = try #require(WKTTimestamp(rfc3339: "2099-01-01T01:00:00Z"))
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-token.impersonated-access-token",
      expireTime: expectedExpiry
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let impCreds = try ImpersonatedCredentials(
      sourceCredentials: sourceCreds,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock)
    )

    let accessToken = try await impCreds.accessToken()
    #expect(accessToken.token == "mock-token.impersonated-access-token")
    #expect(accessToken.expirationDate == expectedExpiry.date)
  }
}
