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
  /// If empty, client libraries default to the comprehensive
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
}

/// Configuration options for Application Default Credentials (ADC).
///
/// Under [AIP-4110](https://google.aip.dev/auth/4110), ADC automatically discovers credentials from
/// `GOOGLE_APPLICATION_CREDENTIALS`, well-known `gcloud` user credentials files, or the link-local
/// Compute Engine Metadata Server (MDS).
///
/// ### Usage Example
/// ```swift
/// let config = ADCConfig().with {
///   $0.quotaProjectID = "my-billing-project"
///   $0.scopes = ["https://www.googleapis.com/auth/cloud-platform"]
/// }
/// let credentials = try Credentials(configuration: .adc(config))
/// ```
///
/// See [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials).
public struct ADCConfig: Sendable {
  /// Optional Google Cloud project ID to bill and charge quota against (`x-goog-user-project`).
  ///
  /// Requires `serviceusage.services.use` permission on the project.
  ///
  /// **Important Precedence**: If the `GOOGLE_CLOUD_QUOTA_PROJECT` environment variable is set,
  /// its value takes precedence over this property.
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override (defaults to `googleapis.com`).
  ///
  /// Override this if your application is operating in a custom sovereign or air-gapped cloud.
  public var universeDomain: String? = nil

  /// Scopes requested for the access token, further restricting what the token can be used for.
  public var scopes: [String] = []

  /// Initializes a new instance of `ADCConfig` without any overrides.
  public init() {}

  /// Configures optional properties of `ADCConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ADCConfig) throws -> Void) rethrows -> ADCConfig {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// Configuration options for Service Account JSON key credentials.
///
/// Under [AIP-4111](https://google.aip.dev/auth/4111), service account credentials sign a local
/// JSON Web Signature (JWS) assertion in memory using RS256 without requiring an initial network
/// round-trip to an authorization server.
///
/// > Warning: service account key files must be kept secure. Do not hardcode their value directly
/// > in source code or check them into version control. Treat service account key files with the
/// > same security precautions as passwords.
///
/// ### Usage Example
/// ```swift
/// let keyData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/service-account.json"))
/// let config = ServiceAccountConfig(keyJSON: keyData).with {
///   $0.accessSpecifier = .scopes(["https://www.googleapis.com/auth/cloud-platform"])
/// }
/// let credentials = try Credentials(configuration: .serviceAccount(config))
/// ```
///
/// See [Service Account Overview](https://cloud.google.com/iam/docs/service-account-overview).
public struct ServiceAccountConfig: Sendable {
  /// The raw Service Account JSON key file contents.
  public let keyJSON: Data

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override.
  ///
  /// When `nil`, defaults to the `"universe_domain"` field in `keyJSON` if non-empty, or `googleapis.com`.
  public var universeDomain: String? = nil

  /// Access specifier (either OAuth 2.0 scopes or JWT audience). Defaults to `.scopes([])`.
  public var accessSpecifier: AccessSpecifier = .scopes([])

  /// Initializes a new instance of `ServiceAccountConfig` with the specified JSON key data.
  ///
  /// - Parameter keyJSON: The raw Service Account JSON key file contents.
  public init(keyJSON: Data) {
    self.keyJSON = keyJSON
  }

  /// Configures optional properties of `ServiceAccountConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ServiceAccountConfig) throws -> Void) rethrows
    -> ServiceAccountConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// Configuration options for Authorized User OAuth 2.0 credentials.
///
/// [User Accounts](https://cloud.google.com/docs/authentication#user-accounts) utilize an OAuth 2.0
/// refresh token obtained through the Authorization Code grant
/// ([RFC 6749 Section 4.1](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1)), typically
/// generated by `gcloud auth application-default login`.
///
/// **Universe Domain Constraint**: User accounts are only supported in the default Google
/// [universe](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) (`googleapis.com`).
/// Initializing user credentials with a custom universe domain fails with ``CredentialsError/notSupported(_:)``.
///
/// > Warning: authorized user key files must be kept secure. Do not hardcode their value directly
/// > in source code or check them into version control. Treat authorized user key files with the
/// > same security precautions as passwords.
///
/// ### Usage Example
/// ```swift
/// let keyData = try Data(contentsOf: URL(fileURLWithPath: "/path/to/authorized-user.json"))
/// let config = UserConfig(keyJSON: keyData).with {
///   $0.quotaProjectID = "my-billing-project"
/// }
/// let credentials = try Credentials(configuration: .user(config))
/// ```
public struct UserConfig: Sendable {
  /// The raw Authorized User JSON file contents.
  public let keyJSON: Data

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  ///
  /// When `nil`, falls back to the `"quota_project_id"` field in `keyJSON` if present.
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) (must be `googleapis.com` or `nil`).
  public var universeDomain: String? = nil

  /// Scopes requested for the access token.
  public var scopes: [String] = []

  /// Initializes a new instance of `UserConfig` with the specified JSON key data.
  ///
  /// - Parameter keyJSON: The raw Authorized User JSON key file contents.
  public init(keyJSON: Data) {
    self.keyJSON = keyJSON
  }

  /// Configures optional properties of `UserConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout UserConfig) throws -> Void) rethrows -> UserConfig {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// Configuration options for Google Cloud Metadata Server (MDS) credentials.
///
/// Under [AIP-4115](https://google.aip.dev/auth/4115), MDS credentials fetch short-lived access tokens
/// for a compute runtime's attached service account from the link-local metadata server
/// (`http://metadata.google.internal`).
///
/// See [Metadata Server Overview](https://cloud.google.com/compute/docs/metadata/overview).
public struct MDSConfig: Sendable {
  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override.
  ///
  /// When `nil`, the universe domain is queried lazily from `/computeMetadata/v1/universe/universe-domain`
  /// on the metadata server.
  public var universeDomain: String? = nil

  /// Scopes requested for the minted access token.
  ///
  /// When empty, the metadata server issues a token with all scopes configured for the attached
  /// service account.
  public var scopes: [String] = []

  /// Initializes a new instance of `MDSConfig` without any overrides.
  public init() {}

  /// Configures optional properties of `MDSConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout MDSConfig) throws -> Void) rethrows -> MDSConfig {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// Configuration options for Service Account Impersonation credentials.
///
/// Under [AIP-4110](https://google.aip.dev/auth/4110), service account impersonation uses a base
/// `sourceCredentials` instance to request short-lived access tokens for `targetPrincipal` via the
/// Google Cloud IAM Service Account Credentials API (`:generateAccessToken`).
///
/// See [Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation).
public struct ImpersonatedServiceAccountConfig: Sendable {
  /// The default scope requested for impersonated service account access tokens.
  public static let defaultScope = "https://www.googleapis.com/auth/cloud-platform"

  /// The base credentials used to authenticate requests to the IAM Credentials API.
  public let sourceCredentials: Credentials

  /// The email address or resource name (`projects/-/serviceAccounts/{email_or_unique_id}`) of the target service account to impersonate.
  public let targetPrincipal: String

  /// Optional ordered sequence of service account email addresses or resource names in a delegation chain.
  ///
  /// Each service account in the chain must be granted `roles/iam.serviceAccountTokenCreator` on the next
  /// service account in the chain, with the final delegate granted token creator access on `targetPrincipal`.
  public var delegates: [String] = []

  /// Scopes requested for the impersonated access token. Defaults to `[defaultScope]`.
  public var scopes: [String] = [defaultScope]

  /// Desired lifetime duration of the impersonated access token (defaults to 3600 seconds / 1 hour).
  public var lifetime: Duration = .seconds(3600)

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target Google Cloud universe domain override.
  ///
  /// When `nil`, defaults to the universe domain of `sourceCredentials`.
  public var universeDomain: String? = nil

  /// Initializes a new instance of `ImpersonatedServiceAccountConfig`.
  ///
  /// - Parameters:
  ///   - sourceCredentials: The base credentials used to authenticate the impersonation request.
  ///   - targetPrincipal: The email address or resource name of the target service account to impersonate.
  public init(
    sourceCredentials: Credentials,
    targetPrincipal: String
  ) {
    self.sourceCredentials = sourceCredentials
    self.targetPrincipal = targetPrincipal
  }

  /// Configures optional properties of `ImpersonatedServiceAccountConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ImpersonatedServiceAccountConfig) throws -> Void) rethrows
    -> ImpersonatedServiceAccountConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}

/// Represents OAuth 2.0 client credentials used for client authentication via HTTP Basic Auth.
public struct ClientAuthentication: Sendable, Equatable, Hashable {
  /// The OAuth client ID.
  public let clientID: String

  /// The optional OAuth client secret.
  public let clientSecret: String?

  /// Initializes client authentication credentials.
  ///
  /// - Parameters:
  ///   - clientID: The OAuth client ID.
  ///   - clientSecret: The optional OAuth client secret.
  public init(clientID: String, clientSecret: String? = nil) {
    self.clientID = clientID
    self.clientSecret = clientSecret
  }
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
  /// - `.idToken`: An OIDC ID token (`urn:ietf:params:oauth:token-type:id_token`).
  /// - `.jwt`: A generic JSON Web Token (`urn:ietf:params:oauth:token-type:jwt`).
  public let subjectTokenType: SubjectTokenType

  /// The Security Token Service (STS) token exchange endpoint.
  ///
  /// Defaults to `https://sts.googleapis.com/v1/token`.
  public let tokenURL: URL

  /// Optional OAuth client credentials used for client authentication via HTTP Basic Auth.
  public var clientAuthentication: ClientAuthentication? = nil

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
    subjectTokenType: SubjectTokenType,
    tokenURL: URL
  ) {
    self.credentialSource = credentialSource
    self.audience = audience
    self.subjectTokenType = subjectTokenType
    self.tokenURL = tokenURL
  }

  /// Configures optional properties of `ExternalAccountConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ExternalAccountConfig) throws -> Void) rethrows
    -> ExternalAccountConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}

extension ExternalAccountConfig {
  /// Represents the type of subject token being exchanged with Google Cloud STS.
  ///
  /// Standard values are defined in [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693).
  public struct SubjectTokenType: RawRepresentable, Sendable, Hashable,
    CustomStringConvertible, ExpressibleByStringLiteral, Codable
  {
    /// The raw string value representing the subject token type URN.
    public let rawValue: String

    /// Initializes a subject token type with the specified raw string value.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Initializes a subject token type from a string literal.
    public init(stringLiteral value: String) {
      self.rawValue = value
    }

    /// A Boolean value indicating whether the token type URN is empty.
    public var isEmpty: Bool {
      rawValue.isEmpty
    }

    /// The string description of the subject token type.
    public var description: String {
      rawValue
    }
  }
}

extension ExternalAccountConfig.SubjectTokenType {
  /// An OIDC ID token as defined in [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693).
  public static let idToken: Self = "urn:ietf:params:oauth:token-type:id_token"

  /// A JSON Web Token as defined in [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693).
  public static let jwt: Self = "urn:ietf:params:oauth:token-type:jwt"
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
    }
  }
}
