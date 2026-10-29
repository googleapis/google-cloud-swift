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
/// You can obtain an `AccessToken` directly from ``Credentials/accessToken()`` when
/// authenticating non-HTTP protocols, database drivers, WebSockets, or third-party clients,
/// or supply one via ``CredentialsConfiguration/accessToken(_:quotaProjectID:universeDomain:)``
/// or ``AccessTokenProvider``.
public struct AccessToken: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible
{
  /// The raw access token string.
  public let token: String

  /// The date and time when the token expires, or `nil` if the token does not have a known expiration.
  public let expirationDate: Date?

  /// Initializes an access token with a raw token string and optional expiration date.
  ///
  /// - Parameters:
  ///   - token: The raw access token string.
  ///   - expirationDate: The date and time when the token expires (defaults to `nil`).
  public init(token: String, expirationDate: Date? = nil) {
    self.token = token
    self.expirationDate = expirationDate
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

/// A type that asynchronously provides access tokens from a custom authentication source.
///
/// Conforming types can be supplied to ``CredentialsConfiguration/accessTokenProvider(_:quotaProjectID:universeDomain:)``
/// to integrate custom token acquisition flows with ``Credentials``.
///
/// When an ``AccessToken`` returned by ``accessToken()`` includes a non-nil ``AccessToken/expirationDate``,
/// ``Credentials`` caches the token in memory, coalesces concurrent refresh requests (singleflight), and
/// proactively refreshes the token in the background before it expires. When ``AccessToken/expirationDate``
/// is `nil`, the token is cached indefinitely without background refresh polling.
///
/// Conforming types must be `Sendable` and provide a thread-safe implementation of ``accessToken()``.
public protocol AccessTokenProvider: Sendable {
  /// Asynchronously retrieves a fresh access token from the provider.
  ///
  /// ### Error Classification
  /// Errors thrown by this method are wrapped in ``CredentialsError/cannotFetchToken(message:underlyingError:)``
  /// (unless already a ``CredentialsError/cannotFetchToken(message:underlyingError:)`` or `CancellationError`).
  /// By default, thrown errors are treated as transient and retried by the background refresh loop.
  /// To signal an unrecoverable, permanent failure that stops background refresh retries, throw
  /// ``CredentialsError/parseError(_:)``, ``CredentialsError/notSupported(_:)``, or
  /// ``CredentialsError/cannotLoadFile(message:underlyingError:)``.
  ///
  /// - Returns: A valid ``AccessToken``.
  /// - Throws: Any error preventing retrieval of the access token.
  func accessToken() async throws -> AccessToken
}
