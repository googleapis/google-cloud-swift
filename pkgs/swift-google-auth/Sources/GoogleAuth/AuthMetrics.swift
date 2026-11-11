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

/// Authentication request type tokens reported in `x-goog-api-client` headers on outgoing
/// token and metadata server requests.
enum AuthRequestType: String, Sendable {
  /// Access token request (`auth-request-type/at`).
  case accessToken = "at"
  /// ID token request (`auth-request-type/it`).
  case idToken = "it"
  /// Metadata server reachability ping (`auth-request-type/mds`).
  case mdsPing = "mds"
}

/// Credential type tokens reported in `x-goog-api-client` headers on outgoing token requests
/// and downstream service RPCs.
///
/// Only the standardized `cred-type` identifiers (`u`, `sa`, `jwt`, `mds`, `imp`) are defined;
/// credential sources without an assigned telemetry token (such as API keys, external accounts,
/// and anonymous credentials) return `nil` and omit `cred-type`.
enum CredentialTypeMetrics: String, Sendable {
  /// Authorized user OAuth 2.0 refresh token credentials (`cred-type/u`).
  case user = "u"
  /// Service account OAuth 2.0 assertion token-exchange flow (`cred-type/sa`).
  case serviceAccountAssertion = "sa"
  /// Service account self-signed JWT credentials per AIP-4111 (`cred-type/jwt`).
  case serviceAccountJWT = "jwt"
  /// Compute Engine / serverless Metadata Server credentials (`cred-type/mds`).
  case mds = "mds"
  /// Impersonated service account credentials (`cred-type/imp`).
  case impersonated = "imp"
}

/// Credential source type tokens reported in `x-goog-api-client` BYOID STS metrics headers.
enum BYOIDSource: String, Sendable {
  /// Subject token supplied programmatically via `SubjectTokenProvider` (`source/programmatic`).
  case programmatic = "programmatic"

  init(_ credentialSource: ExternalAccountConfig.CredentialSource) {
    switch credentialSource {
    case .programmatic:
      self = .programmatic
    }
  }
}

/// Builders for `x-goog-api-client` authentication and BYOID telemetry headers.
enum AuthMetrics {
  /// The HTTP header field name used for client library and auth telemetry (`x-goog-api-client`).
  static let headerName = "x-goog-api-client"

  /// Returns the Swift standard library runtime version string.
  static var swiftRuntimeVersion: String {
    _SwiftStdlibVersion.current.description
  }

  /// Returns the `GoogleAuth` package version string.
  static var authPackageVersion: String {
    PackageVersion.version
  }

  /// Formats the `gl-swift/<version> auth/<version>` prefix shared across auth telemetry headers.
  static func languageAndAuthVersion() -> String {
    "gl-swift/\(swiftRuntimeVersion) auth/\(authPackageVersion)"
  }

  /// Formats the `x-goog-api-client` header value for standard OAuth2, IAM Credentials, and MDS
  /// authentication requests.
  ///
  /// Example output:
  /// `gl-swift/6.3.0 auth/0.6.0 auth-request-type/at cred-type/mds`
  static func tokenRequestHeader(
    requestType: AuthRequestType?,
    credentialType: CredentialTypeMetrics?
  ) -> String {
    var parts = [languageAndAuthVersion()]
    if let requestType {
      parts.append("auth-request-type/\(requestType.rawValue)")
    }
    if let credentialType {
      parts.append("cred-type/\(credentialType.rawValue)")
    }
    return parts.joined(separator: " ")
  }

  /// Formats the `x-goog-api-client` header value for External Account (BYOID) STS token exchange
  /// requests.
  ///
  /// Example output:
  /// `gl-swift/6.3.0 auth/0.6.0 google-byoid-sdk source/programmatic sa-impersonation/false config-lifetime/false`
  static func byoidHeader(
    source: BYOIDSource,
    saImpersonation: Bool,
    configLifetime: Bool
  ) -> String {
    "\(languageAndAuthVersion()) google-byoid-sdk source/\(source.rawValue) sa-impersonation/\(saImpersonation) config-lifetime/\(configLifetime)"
  }
}
