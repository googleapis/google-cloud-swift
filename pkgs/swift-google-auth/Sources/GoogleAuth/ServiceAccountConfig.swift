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
