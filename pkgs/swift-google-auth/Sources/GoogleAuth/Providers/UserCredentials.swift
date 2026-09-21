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

internal struct UserCredentialsParser: CredentialSourceParser {
  internal static let type = "authorized_user"

  internal init() {}

  internal func parse(
    config: [String: Any],
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider {
    let keyJSON = try JSONSerialization.data(withJSONObject: config)
    return try UserCredentials(
      keyJSON: keyJSON,
      quotaProjectID: quotaProjectID,
      universeDomain: universeDomain,
      scopes: scopes
    )
  }
}

/// An authentication provider backed by an Authorized User OAuth 2.0 credentials file.
///
/// [User Accounts](https://cloud.google.com/docs/authentication#user-accounts) represent human developers
/// or administrators managed as Google Accounts via Google Workspace or Cloud Identity. These credentials
/// utilize an OAuth 2.0 refresh token obtained through the standard Authorization Code grant
/// ([RFC 6749 Section 4.1](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1)), typically created by running
/// `gcloud auth application-default login`.
///
/// The credentials automatically exchange the refresh token for short-lived access tokens via Google's token
/// endpoint (`https://oauth2.googleapis.com/token`) before expiry.
///
/// **Universe Domain Constraint**: User accounts are only supported in the default Google Cloud universe
/// (`googleapis.com`). Initializing user credentials in a custom universe domain throws `CredentialsError.notSupported`.
///
/// **Quota Projects**: Because user credentials are not associated with a specific Google Cloud project,
/// APIs typically require a quota project ID to attribute billing and rate limits. The project ID is sent
/// via the `x-goog-user-project` HTTP header.
typealias UserCredentials = UserCredentialsGeneric<ContinuousClock>

/// Generic implementation of authorized user credentials parameterized by clock type.
struct UserCredentialsGeneric<C: Clock>: CredentialsProvider, Sendable
where C.Instant.Duration == Duration {
  private let cache: TokenCache<C>
  private let quotaProjectID: String?
  private let universeDomain: String?

  /// Dependency injection for tests
  init(
    user: UserAccountData,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String]? = nil,
    httpClient: AuthHTTPClient,
    retryConfiguration: RetryConfiguration,
    clock: C
  ) throws {
    if let universeDomain = universeDomain, universeDomain != defaultUniverseDomain {
      throw CredentialsError.notSupported(
        "User accounts are not supported in custom universes: \(universeDomain)")
    }
    self.quotaProjectID = quotaProjectID ?? user.quotaProjectId
    self.universeDomain = universeDomain

    // Resolve Token URI
    guard
      let resolvedUri = URL(
        string: user.tokenUri ?? "https://oauth2.googleapis.com/token"
      )
    else {
      throw CredentialsError.parseError("Invalid token URI in UserAccountData")
    }

    let provider = UserAccountTokenProvider(
      user: user,
      scopes: scopes,
      tokenUri: resolvedUri,
      retryConfiguration: retryConfiguration,
      httpClient: httpClient
    )

    self.cache = TokenCache(
      provider: provider,
      clock: clock,
      isRetryable: { UserAccountTokenProvider.isRetryable($0) }
    )
  }

  // MARK: - CredentialsProvider

  func headers() async throws -> AuthHeaders {
    let token = try await cache.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let quotaProjectID = quotaProjectID {
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }

  func universeDomain() async -> String? {
    return self.universeDomain
  }
}

extension UserCredentialsGeneric where C == ContinuousClock {
  /// Initializes `UserCredentials` from a raw JSON data payload.
  ///
  /// - Parameters:
  ///   - keyJSON: The JSON data containing the user account credentials.
  ///   - quotaProjectID: An optional project ID used for quota and billing purposes.
  ///   - universeDomain: An optional universe domain to constrain the credentials to (defaults to `googleapis.com`).
  ///   - scopes: An optional array of OAuth 2.0 scopes to request.
  /// - Throws: A `CredentialsError.parseError` if the JSON data is invalid or missing required fields.
  init(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String]? = nil
  ) throws {
    let key: UserAccountData
    do {
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      key = try decoder.decode(UserAccountData.self, from: keyJSON)
    } catch {
      throw CredentialsError.parseError(
        "Failed to parse User Account key JSON: \(error.localizedDescription)"
      )
    }

    try self.init(
      user: key,
      quotaProjectID: quotaProjectID,
      universeDomain: universeDomain,
      scopes: scopes,
      httpClient: AuthHTTPClient(),
      retryConfiguration: .defaultConfiguration,
      clock: ContinuousClock()
    )
  }
}
