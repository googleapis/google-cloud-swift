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

/// Coordinates the asynchronous resolution of a raw subject token and its subsequent STS token exchange.
///
/// Executes a two-step token acquisition workflow:
/// 1. Calls `SubjectTokenProvider.subjectToken()` to obtain a raw third-party identity token
///    (e.g., OIDC JWT, SAML assertion, or Apple Account identity token).
/// 2. Posts the subject token to Google's Security Token Service (STS) endpoint using
///    an [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693) token exchange grant,
///    receiving a short-lived Google Cloud access token.
///
/// - SeeAlso: [RFC 8693: OAuth 2.0 Token Exchange](https://datatracker.ietf.org/doc/html/rfc8693)
/// - SeeAlso: [AIP-4117: Workforce and Workload Identity Federation](https://google.aip.dev/auth/4117)
struct ExternalAccountTokenProvider: TokenProvider, Sendable {
  /// The underlying supplier providing raw third-party subject tokens.
  private let subjectTokenProvider: any SubjectTokenProvider

  /// The STS client executing the RFC 8693 token exchange HTTP request.
  private let stsHandler: STSHandler

  /// The Security Token Service endpoint URL (typically `https://sts.googleapis.com/v1/token`).
  private let tokenURL: URL

  /// The URI identifier specifying the format of the subject token (e.g. `urn:ietf:params:oauth:token-type:jwt`).
  private let subjectTokenType: String

  /// The STS audience resource name identifying the target workload or workforce identity pool provider.
  private let audience: String

  /// The optional list of OAuth 2.0 scopes requested for the federated access token.
  private let scopes: [String]

  /// The client project ID required for billing and quota attribution when using workforce pools.
  private let workforcePoolUserProject: String?

  /// An optional client ID for authenticating with confidential workforce identity pools.
  private let clientID: String?

  /// An optional client secret for authenticating with confidential workforce identity pools.
  private let clientSecret: String?

  /// The retry configuration controlling backoff and attempt limits for token exchange requests.
  private let retryConfiguration: RetryConfiguration?

  /// Initializes a new instance of `ExternalAccountTokenProvider`.
  ///
  /// - Parameters:
  ///   - subjectTokenProvider: Supplier providing third-party subject tokens.
  ///   - tokenURL: Security Token Service endpoint URL.
  ///   - subjectTokenType: STS token type identifier URI.
  ///   - audience: STS audience resource name.
  ///   - scopes: Requested OAuth 2.0 scopes.
  ///   - workforcePoolUserProject: Quota/billing project ID for workforce pools.
  ///   - clientID: Optional client ID for workforce pool authentication.
  ///   - clientSecret: Optional client secret for workforce pool authentication.
  ///   - retryConfiguration: Optional retry configuration.
  ///   - httpClient: HTTP client instance.
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

  /// Fetches a fresh Google Cloud access token by retrieving a subject token and exchanging it via STS.
  ///
  /// - Returns: A valid `Token` containing the exchanged access token string and expiration date.
  /// - Throws: An error if subject token acquisition fails or STS rejects the exchange request.
  @concurrent
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

  /// Evaluates whether an error encountered during STS token exchange is eligible for retry.
  ///
  /// - Parameter error: The error encountered.
  /// - Returns: `true` for transient HTTP status codes (5xx, 429, 408) or network errors; `false` otherwise.
  static func isRetryable(_ error: Error) -> Bool {
    if let authError = error as? AuthHTTPError, let status = authError.statusCode {
      return status >= 500 || status == 429 || status == 408
    }
    return true
  }
}

/// Credentials backing [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
/// and [Workforce Identity Federation](https://cloud.google.com/iam/docs/workforce-identity-federation).
///
/// External account credentials allow applications to access Google Cloud resources using credentials
/// from external identity providers (such as AWS, Azure Active Directory, Okta, Ping, or Apple Account)
/// without downloading or managing long-lived Google Cloud service account keys.
///
/// ### Architecture
/// 1. A third-party credential supplier (`SubjectTokenProvider`) supplies a raw identity token.
/// 2. The token is sent to the Google Cloud Security Token Service (STS) endpoint via
///    [RFC 8693 Token Exchange](https://datatracker.ietf.org/doc/html/rfc8693) to obtain a short-lived
///    Google Cloud federated access token.
/// 3. If accessing workforce pools, `workforcePoolUserProject` specifies the Google Cloud project used
///    for quota and billing attribution.
///
/// - SeeAlso: [Workforce Identity Federation Documentation](https://cloud.google.com/iam/docs/workforce-identity-federation)
/// - SeeAlso: [AIP-4117: Workforce and Workload Identity Federation](https://google.aip.dev/auth/4117)
struct ExternalAccountCredentials: CredentialsProvider, Sendable {
  /// The token cache handling proactive refresh and jittered expiration management.
  private let cache: TokenCache<ContinuousClock>

  /// The supplier providing third-party subject tokens.
  let subjectTokenProvider: any SubjectTokenProvider

  /// The Security Token Service audience identifying the workforce or workload pool provider.
  let audience: String

  /// The URI specifying the format of the subject token.
  let subjectTokenType: String

  /// The Security Token Service endpoint URL.
  let tokenURL: URL

  /// An optional client ID for workforce identity pool authentication.
  let clientID: String?

  /// An optional client secret for workforce identity pool authentication.
  let clientSecret: String?

  /// An optional service account email to impersonate after initial STS exchange.
  let targetPrincipal: String?

  /// The project ID to attribute quota and billing to when accessing workforce pools.
  let workforcePoolUserProject: String?

  /// The requested OAuth 2.0 scopes.
  let scopes: [String]

  /// The target Google Cloud universe domain.
  let universeDomain: String?

  /// Initializes a new instance of `ExternalAccountCredentials`.
  ///
  /// - Parameters:
  ///   - credentialSource: The source supplier for subject tokens (e.g. `.programmatic(provider)`).
  ///   - audience: The STS audience resource name.
  ///   - subjectTokenType: The STS token type URI.
  ///   - tokenURL: The STS token endpoint URL.
  ///   - clientID: Optional client ID for workforce pool authentication.
  ///   - clientSecret: Optional client secret for workforce pool authentication.
  ///   - targetPrincipal: Optional service account to impersonate (currently unsupported).
  ///   - workforcePoolUserProject: Optional quota project for workforce identity pools.
  ///   - scopes: Array of requested OAuth 2.0 scopes.
  ///   - universeDomain: Target universe domain.
  ///   - retryConfiguration: Optional retry policy configuration.
  ///   - httpClient: HTTP client instance.
  /// - Throws: `CredentialsError.parseError` if parameters are invalid or `CredentialsError.notSupported`
  ///   if unsupported features (such as `targetPrincipal` impersonation) are specified.
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

    let effectiveScopes = scopes.isEmpty ? [ExternalAccountConfig.defaultScope] : scopes

    self.subjectTokenProvider = subjectTokenProvider
    self.audience = audience
    self.subjectTokenType = subjectTokenType
    self.tokenURL = tokenURL
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.targetPrincipal = targetPrincipal
    self.workforcePoolUserProject = workforcePoolUserProject
    self.scopes = effectiveScopes
    self.universeDomain = universeDomain

    let provider = ExternalAccountTokenProvider(
      subjectTokenProvider: subjectTokenProvider,
      tokenURL: tokenURL,
      subjectTokenType: subjectTokenType,
      audience: audience,
      scopes: effectiveScopes,
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

  /// Returns authorization headers containing the federated access token.
  ///
  /// Includes `Authorization: <token_type> <access_token>` and, if configured,
  /// `x-goog-user-project: <workforcePoolUserProject>`.
  ///
  /// - Returns: The HTTP header fields to apply to the request.
  /// - Throws: An error if token resolution fails.
  func headers() async throws -> AuthHeaders {
    let token = try await cache.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let project = workforcePoolUserProject {
      headers.append(name: "x-goog-user-project", value: project)
    }
    return headers
  }
}

/// Helper function to validate if the audience refers to a global workforce pool.
///
/// Workforce pool audience strings follow the pattern:
/// `//iam.googleapis.com/locations/{location}/workforcePools/{pool}/providers/{provider}`
///
/// - Parameter audience: The audience string to validate.
/// - Returns: `true` if the audience represents a valid workforce pool format, `false` otherwise.
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
