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
