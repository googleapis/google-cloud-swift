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

    let config = AccessTokenConfig(token: token).with {
      $0.quotaProjectID = "proj-1"
    }
    let configuration = CredentialsConfiguration.accessToken(config)
    #expect(!String(reflecting: config).contains("mock-token.super-secret-access-token"))
    #expect(!String(describing: config).contains("mock-token.super-secret-access-token"))
    #expect(!String(reflecting: configuration).contains("mock-token.super-secret-access-token"))
    #expect(!String(describing: configuration).contains("mock-token.super-secret-access-token"))

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
      configuration: .accessToken(AccessTokenConfig(token: "mock-token.static-token"))
    )

    let token = try await credentials.accessToken()
    #expect(token.token == "mock-token.static-token")
    #expect(token.expirationDate == nil)

    let headers = try await credentials.headers()
    #expect(headers == [("Authorization", "Bearer mock-token.static-token")])
    #expect(try await credentials.universeDomain() == Credentials.defaultUniverseDomain)
    try await credentials.validateUniverseDomain(Credentials.defaultUniverseDomain)
  }

  @Test func staticAccessTokenStructWithExpirationAndQuotaProject() async throws {
    let futureExpiry = Date().addingTimeInterval(3600)
    let expectedToken = AccessToken(token: "mock-token.struct-token", expirationDate: futureExpiry)
    let config = AccessTokenConfig(token: expectedToken).with {
      $0.quotaProjectID = "my-quota-project"
      $0.universeDomain = "custom.universe.com"
    }
    let credentials = try Credentials(configuration: .accessToken(config))

    let token = try await credentials.accessToken()
    #expect(token == expectedToken)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.struct-token"),
        ("x-goog-user-project", "my-quota-project"),
      ]
    )
    #expect(try await credentials.universeDomain() == "custom.universe.com")
    try await credentials.validateUniverseDomain("custom.universe.com")
    await #expect(throws: CredentialsError.self) {
      try await credentials.validateUniverseDomain("mismatch.universe.com")
    }
  }

  @Test func accessTokenConfigNormalizesEmptyQuotaProjectAndUniverseDomain() async throws {
    let staticConfig = AccessTokenConfig(token: "mock-token.empty-norm").with {
      $0.quotaProjectID = ""
      $0.universeDomain = ""
    }
    let staticCreds = try Credentials(configuration: .accessToken(staticConfig))
    let staticHeaders = try await staticCreds.headers()
    #expect(staticHeaders == [("Authorization", "Bearer mock-token.empty-norm")])
    #expect(try await staticCreds.universeDomain() == Credentials.defaultUniverseDomain)

    let provider = MockCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.provider-empty-norm")
    )
    let providerConfig = AccessTokenConfig(provider: provider).with {
      $0.quotaProjectID = ""
      $0.universeDomain = ""
    }
    let providerCreds = try Credentials(configuration: .accessToken(providerConfig))
    let providerHeaders = try await providerCreds.headers()
    #expect(providerHeaders == [("Authorization", "Bearer mock-token.provider-empty-norm")])
    #expect(try await providerCreds.universeDomain() == Credentials.defaultUniverseDomain)
  }

  @Test func staticAccessTokenStringOverloadWithExpirationAndQuotaProject() async throws {
    let futureExpiry = Date().addingTimeInterval(3600)
    let config = AccessTokenConfig(
      token: "mock-token.overload-token",
      expirationDate: futureExpiry
    ).with {
      $0.quotaProjectID = "my-quota-project"
      $0.universeDomain = "custom.universe.com"
    }
    let credentials = try Credentials(configuration: .accessToken(config))

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
    #expect(try await credentials.universeDomain() == "custom.universe.com")
    try await credentials.validateUniverseDomain("custom.universe.com")
    await #expect(throws: CredentialsError.self) {
      try await credentials.validateUniverseDomain("mismatch.universe.com")
    }
  }

  @Test func staticAccessTokenThrowsWhenExpired() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let timeSource = MockTimeSource(currentDate: now)
    let expiry = now.addingTimeInterval(60)

    let config = AccessTokenConfig(token: "mock-token.expiring-token", expirationDate: expiry).with
    {
      $0.quotaProjectID = "proj-1"
    }
    let staticCreds = AccessTokenCredentials(
      config: config,
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

  @Test func staticAccessTokenDebugDescriptionRedactsSecret() throws {
    let config = AccessTokenConfig(token: "mock-token.secret-static-value").with {
      $0.quotaProjectID = "quota-123"
    }
    let staticCreds = AccessTokenCredentials(config: config)
    let debugDesc = String(reflecting: staticCreds)
    #expect(!debugDesc.contains("mock-token.secret-static-value"))
    #expect(debugDesc.contains("[redacted]"))
    #expect(debugDesc.contains("quota-123"))

    let stringDesc = String(describing: staticCreds)
    #expect(!stringDesc.contains("mock-token.secret-static-value"))
    #expect(stringDesc.contains("[redacted]"))

    let credentials = try Credentials(configuration: .accessToken(config))
    #expect(!String(reflecting: credentials).contains("mock-token.secret-static-value"))
    #expect(!String(describing: credentials).contains("mock-token.secret-static-value"))
  }

  // MARK: - Custom AccessTokenProvider Tests

  @Test func customAccessTokenProviderInvokedDirectlyForTokenAndHeaders() async throws {
    let expiry = Date().addingTimeInterval(3600)
    let provider = MockCustomAccessTokenProvider(
      token: AccessToken(token: "mock-token.custom-provider-token-1", expirationDate: expiry)
    )

    let config = AccessTokenConfig(provider: provider).with {
      $0.quotaProjectID = "custom-quota-project"
      $0.universeDomain = "custom.universe.com"
    }
    let credentials = try Credentials(configuration: .accessToken(config))

    let token = try await credentials.accessToken()
    #expect(token.token == "mock-token.custom-provider-token-1")
    #expect(token.expirationDate == expiry)
    #expect(await provider.count == 1)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.custom-provider-token-1"),
        ("x-goog-user-project", "custom-quota-project"),
      ]
    )
    #expect(await provider.count == 2)
    #expect(try await credentials.universeDomain() == "custom.universe.com")
    try await credentials.validateUniverseDomain("custom.universe.com")

    // Updating the provider is reflected immediately on the next call
    let refreshedExpiry = Date().addingTimeInterval(7200)
    await provider.configure(
      token: AccessToken(
        token: "mock-token.custom-provider-token-2", expirationDate: refreshedExpiry)
    )
    let token2 = try await credentials.accessToken()
    #expect(token2.token == "mock-token.custom-provider-token-2")
    #expect(token2.expirationDate == refreshedExpiry)
    #expect(await provider.count == 3)
  }

  @Test func customAccessTokenProviderWrapsThrownErrorsInCannotFetchToken() async throws {
    struct CustomFailure: Error, Equatable {}
    let provider = MockCustomAccessTokenProvider(token: nil, error: CustomFailure())
    let credentials = try Credentials(
      configuration: .accessToken(AccessTokenConfig(provider: provider))
    )

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error))")
      return
    }
    #expect(underlyingError is CustomFailure)
  }

  @Test func customAccessTokenProviderPropagatesCredentialsErrorDirectly() async throws {
    let provider = MockCustomAccessTokenProvider(
      token: nil,
      error: CredentialsError.parseError("invalid configuration")
    )
    let credentials = try Credentials(
      configuration: .accessToken(AccessTokenConfig(provider: provider))
    )

    let thrownError = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case let .parseError(message) = thrownError else {
      Issue.record("Expected CredentialsError.parseError, got \(thrownError)")
      return
    }
    #expect(message == "invalid configuration")

    struct InnerError: Error {}
    let cannotFetch = CredentialsError.cannotFetchToken(
      message: "custom message",
      underlyingError: InnerError()
    )
    await provider.configure(token: nil, error: cannotFetch)

    let thrownCannotFetch = await #expect(throws: CredentialsError.self) {
      _ = try await credentials.accessToken()
    }
    guard case let .cannotFetchToken(fetchMessage, underlyingError) = thrownCannotFetch else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(thrownCannotFetch)")
      return
    }
    #expect(fetchMessage == "custom message")
    #expect(underlyingError is InnerError)
  }

  @Test func customAccessTokenProviderPropagatesCancellationErrorDirectly() async throws {
    let timeSource = MockTimeSource(currentDate: Date())
    let provider = MockCustomAccessTokenProvider(token: nil, error: CancellationError())
    let creds = AccessTokenCredentials(
      config: AccessTokenConfig(provider: provider),
      timeSource: timeSource
    )

    await #expect(throws: CancellationError.self) {
      _ = try await creds.accessToken()
    }
    #expect(await provider.count == 1)

    let expectedToken = AccessToken(
      token: "mock-token.recovered-after-cancel",
      expirationDate: timeSource.now.addingTimeInterval(3600)
    )
    await provider.configure(token: expectedToken, error: nil)

    let recovered = try await creds.accessToken()
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
    let sourceCreds = AccessTokenCredentials(
      config: AccessTokenConfig(token: "mock-token.source-token")
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
