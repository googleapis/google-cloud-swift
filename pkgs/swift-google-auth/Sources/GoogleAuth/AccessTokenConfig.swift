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

/// Configuration options for static or custom provider OAuth 2.0 access token credentials.
///
/// Use `AccessTokenConfig` with ``CredentialsConfiguration/accessToken(_:)`` when supplying a
/// pre-obtained ``AccessToken`` (for example, forwarded by an API gateway or obtained via
/// `gcloud auth print-access-token`) or a custom asynchronous ``AccessTokenProvider``.
///
/// ### Usage Example
/// ```swift
/// // Static access token with a quota project override:
/// let staticConfig = AccessTokenConfig(token: "my-access-token").with {
///   $0.quotaProjectID = "my-billing-project"
/// }
/// let staticCredentials = try Credentials(configuration: .accessToken(staticConfig))
///
/// // Custom asynchronous AccessTokenProvider:
/// let providerConfig = AccessTokenConfig(provider: myTokenProvider).with {
///   $0.quotaProjectID = "my-billing-project"
/// }
/// let providerCredentials = try Credentials(configuration: .accessToken(providerConfig))
/// ```
public struct AccessTokenConfig: Sendable {
  /// Defines how the access token is supplied.
  ///
  /// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
  ///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
  ///   clause in `switch` statements.
  public enum CredentialSource: Sendable {
    /// A static, pre-obtained ``AccessToken``.
    ///
    /// Static access tokens cannot be refreshed automatically. If `token.expirationDate` is set and
    /// has passed, calls to ``Credentials/headers()`` or ``Credentials/accessToken()`` fail with
    /// ``CredentialsError/cannotFetchToken(message:underlyingError:)``.
    case staticToken(AccessToken)

    /// A custom asynchronous ``AccessTokenProvider``.
    ///
    /// Invoked directly on each call to ``Credentials/headers()`` or ``Credentials/accessToken()``.
    /// Providers that perform network requests or expensive operations should implement their own
    /// token caching.
    case provider(any AccessTokenProvider)
  }

  /// The source supplying the access token.
  public let credentialSource: CredentialSource

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override (defaults to `googleapis.com`).
  public var universeDomain: String? = nil

  /// Initializes a new instance of `AccessTokenConfig` with the specified credential source.
  ///
  /// - Parameter credentialSource: The source supplying the access token.
  public init(credentialSource: CredentialSource) {
    self.credentialSource = credentialSource
  }

  /// Initializes a new instance of `AccessTokenConfig` backed by a static ``AccessToken``.
  ///
  /// - Parameter token: The pre-obtained ``AccessToken``.
  public init(token: AccessToken) {
    self.init(credentialSource: .staticToken(token))
  }

  /// Initializes a new instance of `AccessTokenConfig` backed by a static raw token string and optional expiration date.
  ///
  /// - Parameters:
  ///   - token: The raw OAuth 2.0 access token string.
  ///   - expirationDate: The date and time when the token expires, or `nil` if the token does not expire.
  public init(token: String, expirationDate: Date? = nil) {
    self.init(
      credentialSource: .staticToken(AccessToken(token: token, expirationDate: expirationDate)))
  }

  /// Initializes a new instance of `AccessTokenConfig` backed by a custom asynchronous ``AccessTokenProvider``.
  ///
  /// - Parameter provider: The custom provider supplying ``AccessToken`` instances.
  public init(provider: any AccessTokenProvider) {
    self.init(credentialSource: .provider(provider))
  }

  /// Configures optional properties of `AccessTokenConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout AccessTokenConfig) throws -> Void) rethrows
    -> AccessTokenConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}
