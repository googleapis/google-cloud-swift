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
/// @Snippet(path: "AccessTokenConfigSample")
public struct AccessTokenConfig: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  /// The provider supplying the access token.
  public let provider: any AccessTokenProvider

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override (defaults to `googleapis.com`).
  public var universeDomain: String? = nil

  /// Initializes a new instance of `AccessTokenConfig` backed by a custom asynchronous ``AccessTokenProvider``.
  ///
  /// ``Credentials`` invokes ``AccessTokenProvider/accessToken()`` directly on each call to
  /// ``Credentials/headers()`` or ``AnyAccessTokenProvider/accessToken()``. Providers that perform network
  /// requests or expensive operations should implement their own token caching.
  ///
  /// - Parameter provider: The custom provider supplying ``AccessToken`` instances.
  public init(provider: any AccessTokenProvider) {
    self.provider = provider
  }

  /// Initializes a new instance of `AccessTokenConfig` backed by a static ``AccessToken``.
  ///
  /// Static access tokens cannot be refreshed automatically. If `token.expirationDate` is set and
  /// has passed, calls to ``Credentials/headers()`` or ``AnyAccessTokenProvider/accessToken()`` fail with
  /// ``CredentialsError/cannotFetchToken(message:underlyingError:)``.
  ///
  /// - Parameter token: The pre-obtained ``AccessToken``.
  public init(token: AccessToken) {
    self.init(token: token, timeSource: SystemTimeSource())
  }

  /// Initializes a new instance of `AccessTokenConfig` backed by a static raw token string and optional expiration date.
  ///
  /// Static access tokens cannot be refreshed automatically. If `expirationDate` is set and
  /// has passed, calls to ``Credentials/headers()`` or ``AnyAccessTokenProvider/accessToken()`` fail with
  /// ``CredentialsError/cannotFetchToken(message:underlyingError:)``.
  ///
  /// - Parameters:
  ///   - token: The raw OAuth 2.0 access token string.
  ///   - expirationDate: The date and time when the token expires, or `nil` if the token does not expire.
  public init(token: String, expirationDate: Date? = nil) {
    self.init(token: AccessToken(token: token, expirationDate: expirationDate))
  }

  init(token: AccessToken, timeSource: any TimeSource) {
    self.init(provider: StaticAccessTokenProvider(token: token, timeSource: timeSource))
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

  public var description: String {
    debugDescription
  }

  public var debugDescription: String {
    "AccessTokenConfig(provider: AccessTokenProvider, quotaProjectID: \(String(describing: quotaProjectID)), universeDomain: \(String(describing: universeDomain)))"
  }
}

/// An internal ``AccessTokenProvider`` returning a fixed ``AccessToken`` and validating its expiration.
struct StaticAccessTokenProvider: AccessTokenProvider, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Error thrown as the underlying error when a static access token has expired.
  private struct ExpiredTokenError: Error, Sendable, CustomStringConvertible {
    let expirationDate: Date

    var description: String {
      "Static access token expired at \(expirationDate)."
    }
  }

  let token: AccessToken
  let timeSource: any TimeSource

  func accessToken() async throws -> AccessToken {
    // Evaluate against exact wall-clock time (`<= now`) without refresh slack because static tokens
    // cannot be refreshed early, and applying a refresh margin would prematurely reject valid tokens.
    if let expirationDate = token.expirationDate, expirationDate <= timeSource.now {
      throw CredentialsError.cannotFetchToken(
        message: "The static access token has expired and cannot be refreshed.",
        underlyingError: ExpiredTokenError(expirationDate: expirationDate)
      )
    }
    return token
  }

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    "StaticAccessTokenProvider(token: \"[redacted]\", expirationDate: \(String(describing: token.expirationDate)))"
  }
}
