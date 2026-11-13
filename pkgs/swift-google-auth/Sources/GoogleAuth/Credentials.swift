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

/// The default Google Cloud universe domain (`googleapis.com`).
///
/// A "universe" is an isolated Google Cloud environment, such as the standard universe
/// (`googleapis.com`) or a sovereign, air-gapped, or dedicated deployment. The universe domain
/// is used to construct base URLs for Google Cloud service endpoints.
///
/// See [Google Cloud Universes](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones).
let defaultUniverseDomain = "googleapis.com"

func nonEmpty(_ value: String?) -> String? {
  guard let value = value, !value.isEmpty else {
    return nil
  }
  return value
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
  ///    Google Cloud runtime environments (Google Compute Engine, GKE, Cloud Run). Setting `NO_GCE_CHECK` to
  ///    `"true"` or `"1"` (case-insensitive) skips probing the metadata server and throws
  ///    ``CredentialsError/credentialsNotFound(_:)`` immediately if no local credentials were found.
  ///
  /// When resolving `.adc()`, ``Credentials/init(configuration:)`` performs synchronous filesystem I/O to read and parse
  /// local credential files (assuming small JSON configuration files). Avoid resolving `.adc()` repeatedly on the
  /// hot path inside asynchronous request handlers; instead, initialize ``Credentials`` (or your service client) once
  /// at application startup and reuse the instance across requests.
  ///
  /// - Parameter config: The configuration specifying optional quota project, universe domain, and scope overrides.
  case adc(ADCConfig = ADCConfig())

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
  /// - Parameter config: The configuration specifying the Service Account JSON key and optional overrides.
  case serviceAccount(ServiceAccountConfig)

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
  /// ``CredentialsError/notSupported(_:)``.
  ///
  /// > Warning: authorized user key files must be kept secure. Do not hardcode their value directly
  /// > in source code or check them into version control. Treat authorized user key files with the
  /// > same security precautions as passwords.
  ///
  /// - Parameter config: The configuration specifying the Authorized User JSON key and optional overrides.
  case user(UserConfig)

  /// External account credentials configuration for Workload and Workforce Identity Federation.
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
  case externalAccount(ExternalAccountConfig)

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

  /// Impersonates a target Google Cloud service account using a base source credential.
  ///
  /// [Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation) allows an
  /// authenticated principal (such as a user account or another service account) with the
  /// `roles/iam.serviceAccountTokenCreator` role to obtain short-lived access tokens acting as a target service account
  /// via the IAM Credentials API (`projects/-/serviceAccounts/{principal}:generateAccessToken`).
  ///
  /// - Parameter config: The configuration specifying the source credentials, target service account, and optional delegation chain.
  case impersonatedServiceAccount(ImpersonatedServiceAccountConfig)

  /// Explicitly queries the Google Cloud Metadata Server (MDS) for the runtime's attached service account.
  ///
  /// In Google Cloud environments such as [Google Compute Engine (GCE)](https://cloud.google.com/compute),
  /// [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine), and
  /// [Cloud Run](https://cloud.google.com/run), workloads run with an attached service account accessible
  /// via the link-local [Metadata Server](https://cloud.google.com/compute/docs/metadata/overview)
  /// (`http://metadata.google.internal`) according to [AIP-4115](https://google.aip.dev/auth/4115).
  ///
  /// Unlike ``adc(_:)``, `.mds` skips local credential file discovery
  /// (`GOOGLE_APPLICATION_CREDENTIALS` and well-known `gcloud` files) and ignores `NO_GCE_CHECK`.
  /// The default metadata server endpoint can be overridden via the `GCE_METADATA_HOST` environment
  /// variable during local testing or emulation.
  ///
  /// To act as a different service account than the one attached to the compute instance, pass
  /// `Credentials(configuration: .mds())` as the `sourceCredentials` of ``ImpersonatedServiceAccountConfig``
  /// via ``impersonatedServiceAccount(_:)``.
  ///
  /// - Parameter config: The configuration specifying optional quota project, universe domain, and scope overrides.
  case mds(MDSConfig = MDSConfig())

  /// Credentials backed by a static OAuth 2.0 ``AccessToken`` or a custom asynchronous ``AccessTokenProvider``.
  ///
  /// Useful when an access token has already been acquired out-of-band (for example, forwarded by an
  /// API gateway or obtained via `gcloud auth print-access-token` in a CI pipeline) or when integrating
  /// a custom token acquisition source.
  ///
  /// - Parameter config: The configuration specifying the access token source and optional overrides.
  case accessToken(AccessTokenConfig)
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

  /// Asynchronously retrieves the Google Cloud universe domain associated with these credentials.
  ///
  /// - Returns: The universe domain string (defaults to `"googleapis.com"`).
  func universeDomain() async throws -> String

  /// Validates that the universe domain of these credentials matches `expectedUniverseDomain`.
  ///
  /// - Parameter expectedUniverseDomain: The universe domain expected by the caller.
  /// - Throws: A ``CredentialsError`` if the universe domain cannot be resolved or does not match `expectedUniverseDomain`.
  func validateUniverseDomain(_ expectedUniverseDomain: String) async throws
}

extension CredentialsProvider {
  func universeDomain() async throws -> String {
    return defaultUniverseDomain
  }

  func validateUniverseDomain(_ expectedUniverseDomain: String) async throws {
    let credUniverse = try await self.universeDomain()
    guard credUniverse == expectedUniverseDomain else {
      throw CredentialsError.parseError(
        "The configured universe domain (\(expectedUniverseDomain)) does not match the universe domain found in the credentials (\(credUniverse))."
      )
    }
  }
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
/// ### Lifecycle and Reuse
/// ``Credentials`` instances are thread-safe (`Sendable`) and designed to be initialized once at
/// application startup and shared across requests or clients.
///
/// Initializing ``Credentials`` with `.adc()` performs synchronous filesystem I/O to read and parse local
/// credential files (assuming small JSON configuration files) and starts an in-memory token cache with
/// a background refresh loop. Avoid creating new ``Credentials`` (or service client) instances inside
/// asynchronous request handlers on the hot path, as doing so performs synchronous file I/O on Swift's
/// cooperative thread pool and discards cached access tokens.
///
/// ### Usage Example
/// ```swift
/// // Automatically use Application Default Credentials (recommended):
/// let credentials = try Credentials()
/// let headers = try await credentials.headers()
///
/// // Or use explicit configuration with a custom quota project:
/// let config = ADCConfig().with {
///   $0.quotaProjectID = "my-billing-project"
/// }
/// let customCredentials = try Credentials(configuration: .adc(config))
/// ```
public struct Credentials: Sendable {
  /// The default Google Cloud universe domain (`"googleapis.com"`).
  public static let defaultUniverseDomain = GoogleAuth.defaultUniverseDomain

  let credentialsProvider: any CredentialsProvider

  /// Initializes credentials using a specific configuration (defaults to automatic ADC resolution).
  ///
  /// When `configuration` is `.adc()`, this initializer performs synchronous filesystem I/O to locate,
  /// read, and parse local credential files (such as `GOOGLE_APPLICATION_CREDENTIALS` or the well-known
  /// `gcloud` credentials file, which are assumed to be small JSON configuration files). Prefer
  /// initializing ``Credentials`` at application startup and reusing the instance rather than calling
  /// this initializer repeatedly inside asynchronous request handlers.
  ///
  /// - Parameter configuration: The configuration describing the credential source and parameters.
  /// - Throws: A `CredentialsError` if the credentials cannot be loaded or parsed, if the configuration is
  ///   unsupported, or ``CredentialsError/credentialsNotFound(_:)`` when `.adc()` finds no local credentials and
  ///   `NO_GCE_CHECK` disables probing the metadata server.
  public init(configuration: CredentialsConfiguration = .adc()) throws {
    try self.init(
      configuration: configuration,
      environment: ProcessInfo.processInfo.environment
    )
  }

  init(
    configuration: CredentialsConfiguration = .adc(),
    environment: [String: String]
  ) throws {
    self.credentialsProvider = try Self.resolveCredentialsProvider(
      configuration: configuration,
      environment: environment
    )
  }

  /// A type-erased ``AnyAccessTokenProvider`` backed by these credentials if they produce OAuth 2.0
  /// access tokens, or `nil` if this credential type does not use access tokens (such as
  /// ``CredentialsConfiguration/anonymous`` or ``CredentialsConfiguration/apiKey(_:)``).
  ///
  /// The returned ``AnyAccessTokenProvider`` shares the in-memory token cache and proactive
  /// background refresh loop of this ``Credentials`` instance.
  ///
  /// ### Usage Example
  /// @Snippet(path: "AccessTokenProviderSample")
  public var accessTokenProvider: AnyAccessTokenProvider? {
    guard let tokenProvider = self.credentialsProvider as? any AccessTokenProvider else {
      return nil
    }
    return AnyAccessTokenProvider(tokenProvider)
  }

  /// Asynchronously retrieves the request headers required to authenticate a request.
  ///
  /// Returns cached headers if valid, or waits for an active refresh if the token is missing or expired.
  ///
  /// - Returns: The HTTP header fields to apply to the request.
  /// - Throws: A `CredentialsError` if token resolution fails.
  public func headers() async throws -> AuthHeaders {
    return try await self.credentialsProvider.headers()
  }

  /// Asynchronously retrieves the Google Cloud universe domain associated with these credentials.
  ///
  /// A "universe" is an isolated Google Cloud environment, such as the default universe
  /// (`googleapis.com`) or a sovereign/air-gapped deployment. Client libraries compare the
  /// credentials' universe domain with the client's configured universe domain before sending
  /// requests.
  ///
  /// For most credential types, this returns the configured universe domain (or `"googleapis.com"`
  /// by default) immediately. For Metadata Server (MDS) credentials without an explicit universe
  /// domain override, this queries `/computeMetadata/v1/universe/universe-domain` on the metadata
  /// server and caches the result.
  ///
  /// - Returns: The universe domain string (e.g., `"googleapis.com"`).
  /// - Throws: A ``CredentialsError`` if resolving the universe domain from the metadata server fails.
  public func universeDomain() async throws -> String {
    return try await self.credentialsProvider.universeDomain()
  }

  /// Validates that the universe domain associated with these credentials matches `expectedUniverseDomain`.
  ///
  /// For `.anonymous` credentials, this method succeeds without performing a comparison so
  /// unauthenticated callers can access public resources in any universe domain.
  ///
  /// - Parameter expectedUniverseDomain: The universe domain expected by the caller (e.g., the client's configured universe domain).
  /// - Throws: A ``CredentialsError`` if resolving the universe domain fails or if the resolved universe domain does not match `expectedUniverseDomain`.
  public func validateUniverseDomain(_ expectedUniverseDomain: String) async throws {
    try await self.credentialsProvider.validateUniverseDomain(expectedUniverseDomain)
  }

  private static func resolveCredentialsProvider(
    configuration: CredentialsConfiguration,
    environment: [String: String]
  ) throws
    -> any CredentialsProvider
  {
    switch configuration {
    case let .adc(config):
      return try ADC.resolve(
        quotaProjectID: config.quotaProjectID,
        universeDomain: config.universeDomain,
        scopes: config.scopes,
        environment: environment
      )
    case .anonymous:
      return AnonymousCredentials()
    case let .serviceAccount(config):
      return try ServiceAccountCredentials(
        keyJSON: config.keyJSON,
        quotaProjectID: config.quotaProjectID,
        universeDomain: config.universeDomain,
        accessSpecifier: config.accessSpecifier
      )
    case let .user(config):
      return try UserCredentials(
        keyJSON: config.keyJSON,
        quotaProjectID: config.quotaProjectID,
        universeDomain: config.universeDomain,
        scopes: config.scopes
      )
    case let .externalAccount(config):
      return try ExternalAccountCredentials(
        credentialSource: config.credentialSource,
        audience: config.audience,
        subjectTokenType: config.subjectTokenType,
        tokenURL: config.tokenURL,
        clientAuthentication: config.clientAuthentication,
        workforcePoolUserProject: config.workforcePoolUserProject,
        scopes: config.scopes,
        universeDomain: config.universeDomain
      )
    case let .apiKey(apiKey):
      return APIKeyCredentials(apiKey: apiKey)
    case let .impersonatedServiceAccount(config):
      return try ImpersonatedCredentials(
        sourceCredentials: config.sourceCredentials.credentialsProvider,
        targetPrincipal: config.targetPrincipal,
        delegates: config.delegates,
        scopes: config.scopes,
        lifetime: config.lifetime,
        quotaProjectID: config.quotaProjectID,
        universeDomain: config.universeDomain
      )
    case let .mds(config):
      return MDSCredentials(
        quotaProjectID: config.quotaProjectID,
        universeDomain: config.universeDomain,
        scopes: config.scopes,
        fromADC: false,
        environment: environment
      )
    case let .accessToken(config):
      return AccessTokenCredentials(config: config)
    }
  }
}
