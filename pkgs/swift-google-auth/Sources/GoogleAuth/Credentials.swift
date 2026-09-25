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

public import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The default Google Cloud universe domain (`googleapis.com`).
///
/// A "universe" is an isolated Google Cloud environment, such as the standard universe
/// (`googleapis.com`) or a sovereign, air-gapped, or dedicated deployment. The universe domain
/// is used to construct base URLs for Google Cloud service endpoints.
///
/// See [Google Cloud Universes](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones).
package let defaultUniverseDomain = "googleapis.com"

/// Represents the access specifier for a service account based token,
/// specifying either OAuth 2.0 scopes or a JWT audience.
///
/// A [Service Account](https://cloud.google.com/iam/docs/service-account-overview) can produce
/// tokens scoped to specific OAuth 2.0 permissions or targeted to a specific service audience.
/// Only one access specifier may be applied for a given credential setup.
///
/// See [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111) and
/// [OAuth 2.0 Scopes](https://developers.google.com/identity/protocols/oauth2/scopes).
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum AccessSpecifier: Sendable, Hashable {
  /// Sets the target audience (`aud`) claim in the token.
  ///
  /// The audience is a JWT claim specifying the intended recipient of the token (i.e., a service endpoint).
  /// The value should be the canonical URL of the target service endpoint, formatted as `https://{SERVICE}/`
  /// (for example, `https://pubsub.googleapis.com/` or `https://bigtable.googleapis.com/`).
  ///
  /// Only one of audience or scopes can be specified for a credentials configuration.
  ///
  /// See [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111).
  case audience(String)

  /// Sets the requested OAuth 2.0 permission scopes in the token.
  ///
  /// Scopes define the *permissions being requested* for this specific session
  /// when interacting with a service (e.g. `https://www.googleapis.com/auth/cloud-platform`
  /// or `https://www.googleapis.com/auth/devstorage.read_write`).
  ///
  /// IAM permissions, on the other hand, define the *underlying capabilities*
  /// the service account possesses within Google Cloud (e.g. `storage.buckets.delete`).
  /// When a token generated with specific scopes is used, the request must be permitted
  /// by both the service account's underlying IAM permissions and the scopes requested
  /// for the token. Therefore, scopes act as an additional restriction on what the token
  /// can be used for.
  ///
  /// If not specified, client libraries default to the comprehensive
  /// `https://www.googleapis.com/auth/cloud-platform` scope.
  ///
  /// See [Service Account Authorization](https://cloud.google.com/compute/docs/access/service-accounts#authorization)
  /// and [OAuth 2.0 Scopes](https://developers.google.com/identity/protocols/oauth2/scopes).
  case scopes([String])
}

/// Defines the configurations for authenticating Google Cloud API requests.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum CredentialsConfiguration: Sendable {
  /// Automatically resolves credentials using Application Default Credentials (ADC).
  ///
  /// [Application Default Credentials (ADC)](https://cloud.google.com/docs/authentication/application-default-credentials)
  /// is the recommended authentication strategy for Google Cloud applications. ADC automatically discovers
  /// credentials from the execution environment in a standard precedence order:
  /// 1. The file pointed to by the `GOOGLE_APPLICATION_CREDENTIALS` environment variable (service account or user key).
  /// 2. Well-known user credentials file created by `gcloud auth application-default login` on developer workstations.
  /// 3. The link-local [Metadata Server](https://cloud.google.com/compute/docs/metadata/overview) (MDS) on
  ///    Google Cloud runtime environments (Google Compute Engine, GKE, Cloud Run).
  ///
  /// - Parameters:
  ///   - quotaProjectID: The Google Cloud project ID to bill and charge quota against (sent via `x-goog-user-project`).
  ///     Requires `serviceusage.services.use` permission on the project.
  ///     **Important Precedence**: If the `GOOGLE_CLOUD_QUOTA_PROJECT` environment variable is set,
  ///     its value takes precedence over this parameter.
  ///   - universeDomain: Target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) (defaults to `googleapis.com`).
  ///     Override this if your application is operating in a custom sovereign or air-gapped cloud.
  ///   - scopes: Scopes requested for the access token, further restricting what the token can be used for.
  ///   - environment: Optional environment variable dictionary override (defaults to the current process environment).
  case adc(
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String] = [],
    environment: [String: String]? = nil
  )

  /// Returns a stub credential that provides no headers (unauthenticated).
  ///
  /// Anonymous credentials do not provide any authentication information. They are useful for accessing
  /// public resources that do not require authentication (such as public Cloud Storage buckets or public BigQuery
  /// datasets), or when connecting to local service emulators (e.g. Pub/Sub or Firestore emulators) that do not
  /// enforce authentication.
  case anonymous

  /// Explicitly signs JWS assertions locally, in memory, using a Service Account JSON key.
  ///
  /// A [Service Account](https://cloud.google.com/iam/docs/service-account-overview) represents a non-human
  /// identity used by applications and compute workloads. Service account keys contain sensitive RSA private keys
  /// that should be treated with the same security precautions as unencrypted passwords.
  ///
  /// This configuration signs a JSON Web Signature (JWS) assertion locally in memory using RS256 without
  /// requiring an initial network round-trip to an authorization server ([AIP-4111](https://google.aip.dev/auth/4111)).
  /// This is particularly useful when credentials are loaded dynamically from Google Cloud Secret Manager or a
  /// secure key vault.
  ///
  /// > Warning: service account key files must be kept secure. Do not hardcode their value directly
  /// > in source code or check them into version control. Treat service account key files with the
  /// > same security precautions as passwords.
  ///
  /// - Parameters:
  ///   - keyJSON: The raw Service Account JSON key file contents.
  ///   - quotaProjectID: A custom project ID used for billing and quota attribution.
  ///   - universeDomain: [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override.
  ///   - accessSpecifier: Optional access specifier (either OAuth 2.0 scopes or JWT audience).
  case serviceAccount(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    accessSpecifier: AccessSpecifier? = nil
  )

  /// Credentials using Authorized User key files created from user authentication.
  ///
  /// [User Accounts](https://cloud.google.com/docs/authentication#user-accounts) represent developers or
  /// administrators managed as Google Accounts via Google Workspace or Cloud Identity. These credentials utilize
  /// an OAuth 2.0 refresh token obtained through the standard Authorization Code grant
  /// ([RFC 6749 Section 4.1](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1)), typically generated by
  /// `gcloud auth application-default login`.
  ///
  /// The credentials automatically refresh short-lived access tokens using Google's token endpoint before expiry.
  ///
  /// **Universe Domain Constraint**: User accounts are only supported in the default Google [universe](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones)
  /// (`googleapis.com`). Initializing user credentials with a custom universe domain will fail with
  /// `CredentialsError.notSupported`.
  ///
  /// > Warning: authorized user key files must be kept secure. Do not hardcode their value directly
  /// > in source code or check them into version control. Treat authorized user key files with the
  /// > same security precautions as passwords.
  ///
  /// - Parameters:
  ///   - keyJSON: The raw Authorized User JSON file contents.
  ///   - quotaProjectID: An optional project ID used for billing and quota attribution (`x-goog-user-project`).
  ///   - universeDomain: An optional universe domain (must be `googleapis.com` or nil).
  ///   - scopes: Optional OAuth 2.0 scopes to request.
  case user(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String]? = nil
  )

  /// Programmatic credentials configuration for Workload and Workforce Identity Federation.
  ///
  /// [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) and
  /// [Workforce Identity Federation](https://cloud.google.com/iam/docs/workforce-identity-federation) allow
  /// applications running outside of Google Cloud (such as AWS, Azure, GitHub Actions, or on-premises)
  /// to access Google Cloud resources without managing long-lived service account keys.
  ///
  /// A third-party subject token (e.g. OIDC JWT) is exchanged for a short-lived Google Cloud access token via
  /// the Security Token Service (STS) according to [AIP-4117](https://google.aip.dev/auth/4117) and
  /// [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693).
  ///
  /// - Parameter config: The configuration defining the external account parameters and token source.
  case programmaticExternalAccount(ExternalAccountConfig)

  /// An API key credential that associates requests with a Google Cloud project.
  ///
  /// An [API Key](https://cloud.google.com/docs/authentication/api-keys-use) is an encrypted string that
  /// identifies a Google Cloud project for quota and billing purposes without requiring a [principal identity](https://cloud.google.com/iam/docs/overview#principals).
  /// The key is transmitted via the `x-goog-api-key` HTTP request header.
  ///
  /// > Warning: API keys must be kept secure. Do not hardcode API keys directly in source code or check
  /// > them into version control. Treat API keys with the same security precautions as passwords, and restrict
  /// > them in the Google Cloud Console to specific APIs, IP addresses, or application identifiers.
  ///
  /// Note that only some Google Cloud APIs support API keys. Consult the documentation for the specific API you
  /// intend to use before using API keys.
  ///
  /// - Parameter apiKey: The API key string.
  case apiKey(String)
}

/// Configuration options for Workload and Workforce Identity Federation credentials.
///
/// Under [AIP-4117](https://google.aip.dev/auth/4117), external credentials exchange a third-party
/// subject token (such as an OIDC JWT) for a short-lived Google Cloud access token using the
/// Google Cloud Security Token Service (STS) ([RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693)).
///
/// See [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) and
/// [Workforce Identity Federation](https://cloud.google.com/iam/docs/workforce-identity-federation).
public struct ExternalAccountConfig: Sendable {
  /// Defines how the external subject token is supplied.
  ///
  /// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
  ///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
  ///   clause in `switch` statements.
  public enum CredentialSource: Sendable {
    /// The subject token is resolved programmatically via a custom callback.
    case programmatic(subjectTokenProvider: any SubjectTokenProvider)
  }

  /// The source type for external credentials.
  public let credentialSource: CredentialSource

  /// The audience parameter for the Security Token Service (STS) exchange.
  ///
  /// For Workforce Identity Federation, this typically takes the form:
  ///
  /// ```
  /// //iam.googleapis.com/locations/global/workforcePools/$POOL_ID/providers/$PROVIDER_ID
  /// ```
  ///
  /// For Workload Identity Federation, it typically takes the form:
  ///
  /// ```
  /// //iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID
  /// ```
  public let audience: String

  /// The type of the subject token being exchanged.
  ///
  /// Standard values defined in [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693) include:
  /// - `urn:ietf:params:oauth:token-type:id_token`: An OIDC ID token.
  /// - `urn:ietf:params:oauth:token-type:jwt`: A generic JSON Web Token.
  public let subjectTokenType: String

  /// The Security Token Service (STS) token exchange endpoint.
  ///
  /// Defaults to `https://sts.googleapis.com/v1/token`.
  public let tokenURL: URL

  /// Optional OAuth client ID used for client authentication via HTTP Basic Auth.
  public var clientID: String? = nil

  /// Optional OAuth client secret used for client authentication via HTTP Basic Auth.
  public var clientSecret: String? = nil

  /// Optional email of a target service account to impersonate.
  ///
  /// When set, the exchanged STS token is used to call the IAM Credentials API to obtain short-lived
  /// credentials for this target service account via [Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation).
  public var targetPrincipal: String? = nil

  /// Optional user project ID used to assert billing and quota constraints (`x-goog-user-project`).
  ///
  /// This parameter is only allowed when exchanging tokens for a global workforce pool. Setting this
  /// for a non-workforce pool will result in a validation error.
  public var workforcePoolUserProject: String? = nil

  /// The default scope requested for Google Cloud STS token exchange.
  public static let defaultScope = "https://www.googleapis.com/auth/cloud-platform"

  /// Scopes requested for the exchanged token.
  public var scopes: [String] = [defaultScope]

  /// Google Cloud universe domain override.
  public var universeDomain: String? = nil

  /// Initializes a new instance of `ExternalAccountConfig`.
  ///
  /// - Parameters:
  ///   - credentialSource: The source mechanism supplying the external subject token.
  ///   - audience: The STS audience identifier URI.
  ///   - subjectTokenType: The RFC 8693 token type URI of the subject token.
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

  /// Configures optional properties of `ExternalAccountConfig` using a fluent closure.
  public func with(_ configure: (inout ExternalAccountConfig) throws -> Void) rethrows
    -> ExternalAccountConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// A type that can provide authentication headers for Google Cloud API requests.
///
/// Internal protocol implemented by concrete credential backends (e.g. Service Accounts, User Accounts,
/// MDS, API Keys, External Accounts). Conforming types are thread-safe and can be mocked for unit testing.
protocol CredentialsProvider: Sendable {
  /// Asynchronously retrieves the request headers required to authenticate a request.
  ///
  /// - Returns: The HTTP header fields to apply to the request.
  func headers() async throws -> AuthHeaders
}

/// The public entry point to authenticate Google Cloud API requests.
///
/// `Credentials` encapsulates the process of obtaining, caching, and refreshing authentication
/// tokens for calls to Google Cloud services.
///
/// ### Application Default Credentials (ADC)
/// A default-initialized `Credentials()` uses [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials).
/// In Google Cloud runtime environments (GCE, GKE, Cloud Run), it automatically acquires tokens from
/// the local metadata server for the runtime's default service account. On developer workstations,
/// it uses credentials configured via `gcloud auth application-default login`, or the file referenced
/// by `GOOGLE_APPLICATION_CREDENTIALS`.
///
/// ### Token Caching and Proactive Refresh
/// Access tokens generated by `Credentials` are cached in memory and automatically refreshed
/// before expiration in a proactive background loop. Callers invoking `headers()` experience minimal
/// latency on the fast path.
///
/// ### Usage Example
/// ```swift
/// // Automatically use Application Default Credentials (recommended):
/// let credentials = try Credentials()
/// let headers = try await credentials.headers()
///
/// // Or use explicit configuration with a custom quota project:
/// let customCredentials = try Credentials(
///   configuration: .adc(quotaProjectID: "my-billing-project")
/// )
/// ```
public struct Credentials: Sendable {
  let credentialsProvider: any CredentialsProvider

  /// Initializes credentials using a specific configuration (defaults to automatic ADC resolution).
  ///
  /// - Parameter configuration: The configuration describing the credential source and parameters.
  /// - Throws: A `CredentialsError` if the credentials cannot be loaded, parsed, or if the configuration is unsupported.
  public init(configuration: CredentialsConfiguration = .adc()) throws {
    self.credentialsProvider = try Self.resolveCredentialsProvider(
      configuration: configuration)
  }

  /// Asynchronously retrieves the request headers required to authenticate a request.
  ///
  /// Returns cached headers if valid, or waits for an active refresh if the token is missing or expired.
  ///
  /// - Returns: The HTTP header fields to apply to the request.
  public func headers() async throws -> AuthHeaders {
    return try await self.credentialsProvider.headers()
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
