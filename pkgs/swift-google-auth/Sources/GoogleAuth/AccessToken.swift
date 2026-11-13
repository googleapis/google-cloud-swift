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

/// Represents an OAuth 2.0 access token or signed assertion used to authenticate requests.
///
/// An `AccessToken` contains the raw token string and an optional expiration timestamp.
/// You can obtain an `AccessToken` via ``Credentials/accessTokenProvider`` and
/// ``AnyAccessTokenProvider/accessToken()`` when
/// authenticating non-HTTP protocols, database drivers, WebSockets, or third-party clients,
/// or supply one via ``CredentialsConfiguration/accessToken(_:)`` (using ``AccessTokenConfig``)
/// or ``AccessTokenProvider``.
public struct AccessToken: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible
{
  /// The raw access token string.
  public let token: String

  /// The OAuth 2.0 token type (e.g. `"Bearer"`), used internally when formatting `Authorization` headers.
  let tokenType: String

  /// The date and time when the token expires, or `nil` if the token does not have a known expiration.
  public let expirationDate: Date?

  /// Initializes an access token with a raw token string and optional expiration date.
  ///
  /// - Parameters:
  ///   - token: The raw access token string.
  ///   - expirationDate: The date and time when the token expires (defaults to `nil`).
  public init(token: String, expirationDate: Date? = nil) {
    self.init(token: token, tokenType: "Bearer", expirationDate: expirationDate)
  }

  /// Initializes an access token with a raw token string, token type, and optional expiration date.
  init(token: String, tokenType: String, expirationDate: Date? = nil) {
    self.token = token
    self.tokenType = tokenType
    self.expirationDate = expirationDate
  }

  public static func == (lhs: AccessToken, rhs: AccessToken) -> Bool {
    lhs.token == rhs.token && lhs.expirationDate == rhs.expirationDate
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(token)
    hasher.combine(expirationDate)
  }

  /// A textual representation of the access token with the secret value redacted.
  ///
  /// Both `description` and `debugDescription` are explicitly implemented to prevent
  /// Swift's default struct mirror reflection from leaking the raw bearer token in logs.
  public var description: String {
    debugDescription
  }

  /// A debug textual representation of the access token with the secret value redacted.
  public var debugDescription: String {
    "AccessToken(token: \"[redacted]\", expirationDate: \(String(describing: expirationDate)))"
  }
}

// Note: Distinct from internal `TokenProvider` (in `TokenCache.swift`), which models uncached
// `@concurrent` backend token fetches wrapped inside `TokenCache`. `AccessTokenProvider` models a
// ready-to-use token supplier and intentionally omits `@concurrent` under
// `NonisolatedNonsendingByDefault` so downstream `actor` types can conform directly.

/// A type that asynchronously provides access tokens from a custom authentication source.
///
/// Conforming types can be supplied to ``AccessTokenConfig/init(provider:)`` with
/// ``CredentialsConfiguration/accessToken(_:)`` to integrate custom token acquisition flows
/// with ``Credentials``.
///
/// ``Credentials`` invokes ``accessToken()`` directly whenever ``Credentials/headers()`` or
/// ``AnyAccessTokenProvider/accessToken()`` is called. Implementations that fetch tokens over the network
/// or perform expensive operations are responsible for caching and refreshing their own tokens.
///
/// Conforming types must be `Sendable` and provide a thread-safe implementation of ``accessToken()``
/// (for example, an `actor` or a value type backed by synchronized state).
public protocol AccessTokenProvider: Sendable {
  /// Asynchronously retrieves a valid access token from the provider.
  ///
  /// Errors thrown by this method are wrapped in ``CredentialsError/cannotFetchToken(message:underlyingError:)``
  /// (unless already a ``CredentialsError`` or `CancellationError`).
  ///
  /// - Returns: A valid ``AccessToken``.
  /// - Throws: Any error preventing retrieval of the access token.
  func accessToken() async throws -> AccessToken
}

/// A type-erased ``AccessTokenProvider`` that supplies OAuth 2.0 access tokens.
///
/// Obtain an `AnyAccessTokenProvider` from ``Credentials/accessTokenProvider`` when authenticating
/// non-HTTP protocols, database drivers, WebSockets, or third-party clients that require raw
/// ``AccessToken`` values and expiration timestamps instead of HTTP `Authorization` headers, or
/// wrap any ``AccessTokenProvider`` using ``init(_:)``.
///
/// When obtained from ``Credentials/accessTokenProvider`` on a built-in OAuth 2.0 credential source
/// (such as Application Default Credentials, Service Accounts, User Accounts, Metadata Server,
/// Workload Identity Federation, or Service Account Impersonation), `AnyAccessTokenProvider` shares
/// the underlying in-memory token cache and proactive background refresh loop of that ``Credentials``
/// instance.
///
/// ### Usage Example
/// @Snippet(path: "AccessTokenProviderSample")
public struct AnyAccessTokenProvider: AccessTokenProvider, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  private let provider: any AccessTokenProvider

  /// Wraps an ``AccessTokenProvider`` in a type-erased `AnyAccessTokenProvider`.
  ///
  /// - Parameter provider: The underlying access token provider to wrap.
  public init(_ provider: any AccessTokenProvider) {
    if let alreadyErased = provider as? AnyAccessTokenProvider {
      self = alreadyErased
    } else {
      self.provider = provider
    }
  }

  /// Asynchronously retrieves a valid OAuth 2.0 access token from the underlying provider.
  ///
  /// When obtained from ``Credentials/accessTokenProvider``, returns a cached token if valid,
  /// or awaits an active refresh if the token is missing or expired.
  ///
  /// - Returns: A valid ``AccessToken`` containing the raw token string and optional expiration date.
  /// - Throws: ``CredentialsError/cannotFetchToken(message:underlyingError:)`` (or another error
  ///   thrown by a directly wrapped custom ``AccessTokenProvider``) if token resolution fails.
  public func accessToken() async throws -> AccessToken {
    return try await self.provider.accessToken()
  }

  public var description: String {
    debugDescription
  }

  public var debugDescription: String {
    "AnyAccessTokenProvider"
  }
}
