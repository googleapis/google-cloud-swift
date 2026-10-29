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
import GoogleWKT

/// Adapter registered with `CredentialParserRegistry` to construct `ImpersonatedCredentials`
/// from raw `"impersonated_service_account"` ADC JSON `Data`.
struct ImpersonatedServiceAccountParser: CredentialSourceParser {
  static let type = "impersonated_service_account"

  init() {}

  func parse(
    data: Data,
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider {
    let payload: ImpersonatedServiceAccountData
    do {
      payload = try JSONDecoder().decode(ImpersonatedServiceAccountData.self, from: data)
    } catch {
      throw CredentialsError.parseError(
        "Failed to parse Impersonated Service Account key JSON: \(error.localizedDescription)"
      )
    }

    // Extract the embedded credential's `"type"` discriminator so we can route it to the
    // appropriate registered `CredentialSourceParser`.
    guard case let .string(sourceType)? = payload.sourceCredentials["type"] else {
      throw CredentialsError.parseError(
        "Missing or invalid 'type' in Impersonated Service Account source_credentials"
      )
    }

    let sourceData: Data
    do {
      sourceData = try JSONEncoder().encode(payload.sourceCredentials)
    } catch {
      throw CredentialsError.parseError(
        "Failed to encode Impersonated Service Account source_credentials: \(error.localizedDescription)"
      )
    }

    if let universeDomain {
      try validateUniverseDomain(universeDomain)
    }
    let payloadUniverse = nonEmpty(payload.universeDomain)
    if let payloadUniverse {
      try validateUniverseDomain(payloadUniverse)
    }
    if let universeDomain, let payloadUniverse, universeDomain != payloadUniverse {
      throw CredentialsError.parseError(
        "The configured universe_domain (\(universeDomain)) does not match the impersonated_service_account universe_domain (\(payloadUniverse))."
      )
    }
    let effectiveUniverseDomain =
      universeDomain ?? payloadUniverse ?? defaultUniverseDomain
    if case let .string(sourceUniverse)? = payload.sourceCredentials["universe_domain"],
      let nonEmptySourceUniverse = nonEmpty(sourceUniverse)
    {
      try validateUniverseDomain(nonEmptySourceUniverse)
      if nonEmptySourceUniverse != effectiveUniverseDomain {
        throw CredentialsError.parseError(
          "The universe_domain in source_credentials (\(nonEmptySourceUniverse)) does not match the impersonated_service_account universe_domain (\(effectiveUniverseDomain))."
        )
      }
    }
    let effectiveQuotaProjectID =
      nonEmpty(quotaProjectID) ?? nonEmpty(payload.quotaProjectId)

    // Resolve the underlying source credential provider via the registry:
    // - Pass `quotaProjectID: nil` so the outer quota project applies to the impersonated
    //   credentials rather than overriding the source credential's own quota project.
    // - Pass `scopes: []` so `authorized_user` refresh token exchanges use their bound scopes
    //   while `service_account` and `external_account` providers default to `cloud-platform`.
    guard
      let sourceProvider = try CredentialParserRegistry.shared.parse(
        type: sourceType,
        data: sourceData,
        quotaProjectID: nil,
        universeDomain: effectiveUniverseDomain,
        scopes: [],
        environment: environment
      )
    else {
      throw CredentialsError.notSupported(
        "Unsupported source_credentials type in impersonated_service_account: \(sourceType)"
      )
    }

    return try ImpersonatedCredentials(
      sourceCredentials: sourceProvider,
      impersonationURLString: payload.serviceAccountImpersonationUrl,
      delegates: payload.delegates ?? [],
      scopes: scopes,
      lifetime: .seconds(3600),
      quotaProjectID: effectiveQuotaProjectID,
      universeDomain: effectiveUniverseDomain
    )
  }
}

/// An authentication provider that impersonates a Google Cloud service account via the IAM Credentials API.
///
/// Exchanges authentication headers from a base `sourceCredentials` provider for short-lived access tokens
/// representing the target service account, caching and proactively refreshing the resulting token via `TokenCache`.
///
/// - SeeAlso: [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
/// - SeeAlso: [Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation)
struct ImpersonatedCredentials: CredentialsProvider, Sendable {
  private let cache: TokenCache<ContinuousClock>
  let provider: ImpersonatedTokenProvider
  let quotaProjectID: String?
  private let universeDomainOverride: String?

  /// Initializes `ImpersonatedCredentials` for a target service account principal.
  init(
    sourceCredentials: any CredentialsProvider,
    targetPrincipal: String,
    delegates: [String] = [],
    scopes: [String] = [],
    lifetime: Duration = .seconds(3600),
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    httpClient: AuthHTTPClient = AuthHTTPClient(),
    retryConfiguration: RetryConfiguration = .defaultConfiguration
  ) throws {
    if let universeDomain {
      try validateUniverseDomain(universeDomain)
    }
    let effectiveUniverse = universeDomain ?? defaultUniverseDomain
    let resourceName = try Self.normalizeServiceAccountResourceName(targetPrincipal)
    let urlString =
      "https://iamcredentials.\(effectiveUniverse)/v1/\(resourceName):generateAccessToken"

    try self.init(
      sourceCredentials: sourceCredentials,
      impersonationURLString: urlString,
      targetResourceName: resourceName,
      delegates: delegates,
      scopes: scopes,
      lifetime: lifetime,
      quotaProjectID: quotaProjectID,
      universeDomain: universeDomain,
      httpClient: httpClient,
      retryConfiguration: retryConfiguration
    )
  }

  /// Initializes `ImpersonatedCredentials` using an explicit `service_account_impersonation_url`.
  init(
    sourceCredentials: any CredentialsProvider,
    impersonationURLString: String,
    targetResourceName: String? = nil,
    delegates: [String] = [],
    scopes: [String] = [],
    lifetime: Duration = .seconds(3600),
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    httpClient: AuthHTTPClient = AuthHTTPClient(),
    retryConfiguration: RetryConfiguration = .defaultConfiguration
  ) throws {
    guard
      !impersonationURLString.isEmpty,
      let resolvedURL = URL(string: impersonationURLString),
      let scheme = resolvedURL.scheme?.lowercased(),
      scheme == "https",
      resolvedURL.user == nil,
      resolvedURL.password == nil,
      resolvedURL.query == nil,
      resolvedURL.fragment == nil,
      let host = resolvedURL.host,
      !host.isEmpty,
      !resolvedURL.path.isEmpty,
      resolvedURL.path != "/"
    else {
      throw CredentialsError.parseError(
        "Invalid service_account_impersonation_url: '\(impersonationURLString)'"
      )
    }

    guard lifetime >= .seconds(1), lifetime <= .seconds(43_200) else {
      throw CredentialsError.parseError(
        "Impersonated token lifetime must be between 1 and 43200 seconds"
      )
    }
    let lifetimeDuration = try WKTDuration(seconds: lifetime.components.seconds)

    if let universeDomain {
      try validateUniverseDomain(universeDomain)
    }
    let effectiveUniverse = universeDomain ?? defaultUniverseDomain
    if effectiveUniverse != defaultUniverseDomain && sourceCredentials is UserCredentials {
      throw CredentialsError.notSupported(
        "User accounts are not supported in custom universes: \(effectiveUniverse)"
      )
    }
    let lowerHost = host.lowercased()
    if targetResourceName == nil, lowerHost.hasPrefix("iamcredentials.") {
      let urlUniverse = String(host.dropFirst("iamcredentials.".count))
      if urlUniverse != effectiveUniverse {
        throw CredentialsError.parseError(
          "The service_account_impersonation_url host (\(host)) does not match universe_domain (\(effectiveUniverse))."
        )
      }
    }

    let effectiveScopes =
      scopes.isEmpty ? [ImpersonatedServiceAccountConfig.defaultScope] : scopes
    let normalizedDelegates = try delegates.map(Self.normalizeServiceAccountResourceName)
    let resolvedOverride = targetResourceName == nil ? effectiveUniverse : universeDomain

    self.quotaProjectID = (quotaProjectID?.isEmpty == false) ? quotaProjectID : nil
    self.universeDomainOverride = resolvedOverride

    let provider = ImpersonatedTokenProvider(
      sourceCredentials: sourceCredentials,
      iamEndpointURL: resolvedURL,
      targetResourceName: targetResourceName,
      universeDomainOverride: resolvedOverride,
      scopes: effectiveScopes,
      delegates: normalizedDelegates,
      lifetime: lifetimeDuration,
      retryConfiguration: retryConfiguration,
      httpClient: httpClient
    )
    self.provider = provider

    self.cache = TokenCache(
      provider: provider,
      isRetryable: AuthHTTPError.isRetryable
    )
  }

  func headers() async throws -> AuthHeaders {
    let token = try await cache.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let quotaProjectID = quotaProjectID, !quotaProjectID.isEmpty {
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }

  func universeDomain() async throws -> String {
    if let override = self.universeDomainOverride {
      return override
    }
    return try await self.provider.sourceCredentials.universeDomain()
  }

  /// Normalizes and validates a service account email or resource name into
  /// `projects/{project}/serviceAccounts/{principal}` format.
  static func normalizeServiceAccountResourceName(_ principal: String) throws -> String {
    guard
      !principal.isEmpty,
      !principal.contains(".."),
      !principal.unicodeScalars.contains(where: {
        $0.properties.isWhitespace || $0 == "?" || $0 == "#" || $0 == ":"
      })
    else {
      throw CredentialsError.parseError(
        "Invalid service account principal: '\(principal)'"
      )
    }

    if principal.contains("/") {
      let segments = principal.split(separator: "/", omittingEmptySubsequences: false)
      guard
        segments.count == 4,
        segments[0] == "projects",
        !segments[1].isEmpty,
        segments[1] != ".",
        segments[2] == "serviceAccounts",
        !segments[3].isEmpty,
        segments[3] != "."
      else {
        throw CredentialsError.parseError(
          "Invalid service account resource name: '\(principal)'"
        )
      }
      return principal
    }

    guard principal != "." else {
      throw CredentialsError.parseError(
        "Invalid service account principal: '\(principal)'"
      )
    }
    return "projects/-/serviceAccounts/\(principal)"
  }
}
