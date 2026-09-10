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

/// The default Google Cloud universe domain.
package let defaultUniverseDomain = "googleapis.com"

/// Represents the HTTP request header fields required to authenticate an API query.
/// Formatted as an array of key-value tuples to natively support duplicate header names.
public typealias AuthHeaders = [(String, String)]

/// Represents the access specifier for a service account based token,
/// specifying either OAuth 2.0 scopes or a JWT audience.
///
/// It ensures that only one of these access specifiers can be applied
/// for a given credential setup.
///
/// See [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111) and
/// [OAuth 2.0 Scopes](https://developers.google.com/identity/protocols/oauth2/scopes).
public enum AccessSpecifier: Sendable, Hashable {
  /// Use `AccessSpecifier.audience` for setting the audience in the token.
  ///
  /// `aud` is a JWT claim specifying the intended recipient of the token, i.e., a service.
  /// Only one of audience or scopes can be specified for a credentials configuration.
  ///
  /// See [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111).
  case audience(String)

  /// Use `AccessSpecifier.scopes` for setting scopes in the token.
  ///
  /// `scopes` is a JWT claim specifying requested permission(s) for the token.
  /// Only one of audience or scopes can be specified for a credentials configuration.
  ///
  /// Scopes define the *permissions being requested* for this specific session
  /// when interacting with a service. For example, `https://www.googleapis.com/auth/devstorage.read_write`.
  /// IAM permissions, on the other hand, define the *underlying capabilities*
  /// the service account possesses within a system. For example, `storage.buckets.delete`.
  ///
  /// When a token generated with specific scopes is used, the request must be permitted
  /// by both the service account's underlying IAM permissions and the scopes requested
  /// for the token. Therefore, scopes act as an additional restriction on what the token
  /// can be used for. Please see the [Service Account Authorization](https://cloud.google.com/compute/docs/access/service-accounts#authorization)
  /// guide to learn more about scopes and IAM permissions.
  ///
  /// See [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111) and
  /// [OAuth 2.0 Scopes](https://developers.google.com/identity/protocols/oauth2/scopes).
  case scopes([String])
}

/// Defines the configurations for authenticating Google Cloud API requests.
public enum CredentialsConfiguration: Sendable {
  /// Automatically resolves credentials using Application Default Credentials (ADC).
  case adc(
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String] = [],
    environment: [String: String]? = nil
  )

  /// Returns a stub credential that provides no headers (unauthenticated).
  case anonymous

  /// Explicitly signs JWS assertions locally using a Service Account JSON key in memory.
  ///
  /// - Parameters:
  ///   - keyJSON: The raw Service Account JSON key file contents.
  ///   - quotaProjectID: A custom project ID used for billing and quota.
  ///   - universeDomain: Google Cloud universe domain override.
  ///   - accessSpecifier: Optional access specifier (either scopes or audience).
  case serviceAccount(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    accessSpecifier: AccessSpecifier? = nil
  )

  /// Custom credentials using Authorized User key files.
  case user(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String]? = nil
  )

  /// Programmatic credentials configuration for Workforce Identity Federation (OIDC / Apple WIF).
  case programmaticExternalAccount(ExternalAccountConfig)

  /// An API key credential that associates requests with a Google Cloud project.
  ///
  /// Note that only some Cloud APIs support API keys. Consult the documentation for the API you intend to use
  /// before trying to use API keys.
  ///
  /// - Parameters:
  ///   - apiKey: The API key string.
  case apiKey(String)
}

/// Configuration options for external account credentials.
public struct ExternalAccountConfig: Sendable {
  public enum CredentialSource: Sendable {
    /// The subject token is resolved programmatically via a custom callback.
    case programmatic(subjectTokenProvider: any SubjectTokenProvider)
  }

  /// The source type for external credentials.
  public let credentialSource: CredentialSource

  /// The audience parameter for the Security Token Service (STS) exchange.
  /// Typically takes the form of a workforce or workload pool provider URI.
  public let audience: String

  /// The type of the subject token being exchanged (e.g. `"urn:ietf:params:oauth:token-type:id_token"`).
  public let subjectTokenType: String

  /// The Security Token Service (STS) token exchange endpoint.
  public let tokenURL: URL

  /// Optional OAuth client ID used for client authentication.
  public var clientID: String? = nil

  /// Optional OAuth client secret used for client authentication.
  public var clientSecret: String? = nil

  /// Optional email of a target service account to impersonate.
  public var targetPrincipal: String? = nil

  /// Optional user project ID used to assert billing and quota constraints.
  /// Only allowed when exchanging tokens for a global workforce pool.
  public var workforcePoolUserProject: String? = nil

  /// Scopes requested for the exchanged token.
  public var scopes: [String] = []

  /// Google Cloud universe domain override.
  public var universeDomain: String? = nil

  /// Initializes a new instance of `ExternalAccountConfig`.
  ///
  /// - Parameters:
  ///   - credentialSource: The source type for external credentials.
  ///   - audience: The audience parameter for the exchange (e.g. Workforce Pool audience).
  ///   - subjectTokenType: The type of the subject token.
  ///   - tokenURL: The STS token exchange endpoint.
  public init(
    credentialSource: CredentialSource,
    audience: String,
    subjectTokenType: String,
    tokenURL: URL
  ) {
    self.credentialSource = credentialSource
    self.audience = audience
    self.subjectTokenType = subjectTokenType
    self.tokenURL = tokenURL
  }

  /// Configures optional properties of `ExternalAccountConfig` using a closure.
  public func with(_ configure: (inout ExternalAccountConfig) -> Void) -> ExternalAccountConfig {
    var copy = self
    configure(&copy)
    return copy
  }
}

/// A type that can provide authentication headers for Google Cloud API requests.
protocol CredentialsProvider: Sendable {
  /// Asynchronously retrieves the request headers required to authenticate a request.
  ///
  /// - Returns: An array of key-value tuples representing HTTP headers.
  func headers() async throws -> AuthHeaders

  /// Retrieves the universe domain associated with the credentials.
  ///
  /// - Returns: The universe domain string, or nil if not configured or available.
  func universeDomain() async -> String?
}

/// The public entry point to authenticate Google Cloud API requests.
public struct Credentials: Sendable {
  let credentialsProvider: any CredentialsProvider

  /// Initializes credentials using a specific configuration (defaults to automatic ADC resolution).
  public init(configuration: CredentialsConfiguration = .adc()) throws {
    self.credentialsProvider = try Self.resolveCredentialsProvider(
      configuration: configuration)
  }

  /// Asynchronously retrieves the request headers required to authenticate a request.
  public func headers() async throws -> AuthHeaders {
    return try await self.credentialsProvider.headers()
  }

  /// Retrieves the universe domain associated with the credentials.
  public func universeDomain() async -> String? {
    return await self.credentialsProvider.universeDomain()
  }

  // MARK: - Backend Resolvers

  private static func resolveCredentialsProvider(configuration: CredentialsConfiguration) throws
    -> any CredentialsProvider
  {
    switch configuration {
    case let .adc(quotaProjectID, universeDomain, scopes, environment):
      return try ADC.resolve(
        quotaProjectID: quotaProjectID,
        universeDomain: universeDomain,
        scopes: scopes,
        environment: environment ?? ProcessInfo.processInfo.environment
      )
    case .anonymous:
      return AnonymousCredentials()
    case let .serviceAccount(keyJSON, quotaProjectID, universeDomain, accessSpecifier):
      return try ServiceAccountCredentials(
        keyJSON: keyJSON,
        quotaProjectID: quotaProjectID,
        universeDomain: universeDomain,
        accessSpecifier: accessSpecifier
      )
    case let .user(keyJSON, quotaProjectID, universeDomain, scopes):
      return try UserCredentials(
        keyJSON: keyJSON,
        quotaProjectID: quotaProjectID,
        universeDomain: universeDomain,
        scopes: scopes
      )
    case let .programmaticExternalAccount(config):
      return try ExternalAccountCredentials(
        credentialSource: config.credentialSource,
        audience: config.audience,
        subjectTokenType: config.subjectTokenType,
        tokenURL: config.tokenURL,
        clientID: config.clientID,
        clientSecret: config.clientSecret,
        targetPrincipal: config.targetPrincipal,
        workforcePoolUserProject: config.workforcePoolUserProject,
        scopes: config.scopes,
        universeDomain: config.universeDomain
      )
    case let .apiKey(apiKey):
      return ApiKeyCredentials(apiKey: apiKey)
    }
  }
}
