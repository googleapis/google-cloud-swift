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

/// Coordinates the asynchronous resolution of the raw subject token and its subsequent STS token exchange.
struct ExternalAccountTokenProvider: TokenProvider, Sendable {
  private let subjectTokenProvider: any SubjectTokenProvider
  private let stsHandler: STSHandler
  private let tokenURL: URL
  private let subjectTokenType: String
  private let audience: String
  private let scopes: [String]
  private let workforcePoolUserProject: String?
  private let clientID: String?
  private let clientSecret: String?
  private let retryConfiguration: RetryConfiguration?

  init(
    subjectTokenProvider: any SubjectTokenProvider,
    tokenURL: URL,
    subjectTokenType: String,
    audience: String,
    scopes: [String],
    workforcePoolUserProject: String?,
    clientID: String?,
    clientSecret: String?,
    retryConfiguration: RetryConfiguration? = nil,
    httpClient: AuthHTTPClient = AuthHTTPClient()
  ) {
    self.subjectTokenProvider = subjectTokenProvider
    self.tokenURL = tokenURL
    self.subjectTokenType = subjectTokenType
    self.audience = audience
    self.scopes = scopes
    self.workforcePoolUserProject = workforcePoolUserProject
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.retryConfiguration = retryConfiguration
    self.stsHandler = STSHandler(httpClient: httpClient)
  }

  func fetchToken() async throws -> Token {
    let subjectToken = try await subjectTokenProvider.subjectToken()

    let request = ExchangeTokenRequest(
      subjectToken: subjectToken,
      subjectTokenType: subjectTokenType,
      audience: audience,
      scopes: scopes,
      workforcePoolUserProject: workforcePoolUserProject,
      clientAuthentication: clientID.map { ClientAuthentication(id: $0, secret: clientSecret) }
    )

    let response: TokenResponse = try await RetryEngine.retry(
      configuration: retryConfiguration ?? .defaultConfiguration,
      isRetryable: Self.isRetryable
    ) {
      try await stsHandler.exchangeToken(
        request: request,
        url: tokenURL,
        encoding: .urlEncoded
      )
    }

    let expirationDate = Date().addingTimeInterval(Double(response.expiresIn))
    return Token(
      accessToken: response.accessToken,
      tokenType: response.tokenType,
      expirationDate: expirationDate
    )
  }

  static func isRetryable(_ error: Error) -> Bool {
    if let authError = error as? AuthHTTPError, let status = authError.statusCode {
      return status >= 500 || status == 429 || status == 408
    }
    return true
  }
}

/// Credentials backing Workforce Identity Federation (OIDC / Apple WIF) external accounts.
struct ExternalAccountCredentials: CredentialsProvider, Sendable {
  private let cache: TokenCache<ContinuousClock>

  let subjectTokenProvider: any SubjectTokenProvider
  let audience: String
  let subjectTokenType: String
  let tokenURL: URL
  let clientID: String?
  let clientSecret: String?
  let targetPrincipal: String?
  let workforcePoolUserProject: String?
  let scopes: [String]
  let universeDomain: String?

  init(
    credentialSource: ExternalAccountConfig.CredentialSource,
    audience: String,
    subjectTokenType: String,
    tokenURL: URL,
    clientID: String? = nil,
    clientSecret: String? = nil,
    targetPrincipal: String? = nil,
    workforcePoolUserProject: String? = nil,
    scopes: [String] = [],
    universeDomain: String? = nil,
    retryConfiguration: RetryConfiguration? = nil,
    httpClient: AuthHTTPClient = AuthHTTPClient()
  ) throws {
    guard case let .programmatic(subjectTokenProvider) = credentialSource else {
      throw CredentialsError.parseError("Unsupported credential source type")
    }

    // Validate required configuration fields are not empty
    guard !audience.isEmpty else {
      throw CredentialsError.parseError("audience parameter must not be empty")
    }
    guard !subjectTokenType.isEmpty else {
      throw CredentialsError.parseError("subjectTokenType parameter must not be empty")
    }

    if let targetPrincipal = targetPrincipal, !targetPrincipal.isEmpty {
      throw CredentialsError.notSupported(
        "Service account impersonation (targetPrincipal) is not supported yet")
    }

    // Billing constraints validation: workforce pool user project should only be set for global workforce pools.
    if let workforcePoolUserProject = workforcePoolUserProject, !workforcePoolUserProject.isEmpty {
      guard isValidWorkforcePoolAudience(audience) else {
        throw CredentialsError.parseError(
          "workforcePoolUserProject should not be set for non-workforce pool credentials")
      }
    }

    self.subjectTokenProvider = subjectTokenProvider
    self.audience = audience
    self.subjectTokenType = subjectTokenType
    self.tokenURL = tokenURL
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.targetPrincipal = targetPrincipal
    self.workforcePoolUserProject = workforcePoolUserProject
    self.scopes = scopes
    self.universeDomain = universeDomain

    let provider = ExternalAccountTokenProvider(
      subjectTokenProvider: subjectTokenProvider,
      tokenURL: tokenURL,
      subjectTokenType: subjectTokenType,
      audience: audience,
      scopes: scopes,
      workforcePoolUserProject: workforcePoolUserProject,
      clientID: clientID,
      clientSecret: clientSecret,
      retryConfiguration: retryConfiguration,
      httpClient: httpClient
    )

    self.cache = TokenCache(
      provider: provider,
      clock: ContinuousClock(),
      isRetryable: ExternalAccountTokenProvider.isRetryable
    )
  }

  func headers() async throws -> AuthHeaders {
    let token = try await cache.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let project = workforcePoolUserProject {
      headers.append(("X-Goog-User-Project", project))
    }
    return headers
  }

  func universeDomain() async -> String? {
    return self.universeDomain
  }
}

/// Helper function to validate if the audience refers to a global workforce pool.
private func isValidWorkforcePoolAudience(_ audience: String) -> Bool {
  var path = audience
  if path.hasPrefix("//iam.googleapis.com/") {
    path.removeFirst("//iam.googleapis.com/".count)
  }

  let components = path.split(separator: "/", omittingEmptySubsequences: false)
  guard components.count == 6 else { return false }

  return components[0] == "locations"
    && !components[1].isEmpty
    && components[2] == "workforcePools"
    && !components[3].isEmpty
    && components[4] == "providers"
    && !components[5].isEmpty
}
