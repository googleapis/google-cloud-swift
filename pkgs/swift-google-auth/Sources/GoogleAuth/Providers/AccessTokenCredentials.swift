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

/// A static access token credentials provider that returns a pre-obtained ``AccessToken`` without refreshing.
///
/// Unlike refreshable providers backed by `TokenCache` (which begin proactive refresh 4 minutes before
/// expiration), static access tokens cannot be refreshed. Expiration is therefore checked against exact
/// wall-clock time (`expirationDate <= timeSource.now` with zero slack) so short-lived static tokens
/// remain usable until their actual expiration timestamp.
struct StaticAccessTokenCredentials: CredentialsProvider, Sendable, CustomDebugStringConvertible {
  /// The static access token.
  let token: AccessToken

  /// An optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  let quotaProjectID: String?

  /// Target Google Cloud universe domain override.
  let universeDomain: String?

  /// Time source used to evaluate token expiration.
  let timeSource: any TimeSource

  /// Error thrown as the underlying error when a static access token has expired.
  private struct ExpiredTokenError: Error, Sendable, CustomStringConvertible {
    let expirationDate: Date

    var description: String {
      "Static access token expired at \(expirationDate)."
    }
  }

  init(
    token: AccessToken,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    timeSource: any TimeSource = SystemTimeSource()
  ) {
    self.token = token
    self.quotaProjectID = quotaProjectID
    self.universeDomain = universeDomain
    self.timeSource = timeSource
  }

  func accessToken() async throws -> AccessToken {
    // Evaluate against exact wall-clock time (`<= now`) without refresh slack because static tokens
    // cannot be refreshed early, and applying a refresh margin would prematurely reject valid tokens.
    if let expirationDate = self.token.expirationDate, expirationDate <= self.timeSource.now {
      throw CredentialsError.cannotFetchToken(
        message: "The static access token has expired and cannot be refreshed.",
        underlyingError: ExpiredTokenError(expirationDate: expirationDate)
      )
    }
    return self.token
  }

  func headers() async throws -> AuthHeaders {
    let validToken = try await self.accessToken()
    var headers: AuthHeaders = [("Authorization", "Bearer \(validToken.token)")]
    if let quotaProjectID = self.quotaProjectID {
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }

  var debugDescription: String {
    "StaticAccessTokenCredentials(token: \(String(reflecting: token)), quotaProjectID: \(String(describing: quotaProjectID)), universeDomain: \(String(describing: universeDomain)))"
  }
}

/// Bridges a public ``AccessTokenProvider`` to the internal `TokenProvider` protocol used by `TokenCache`.
///
/// Normalizes errors thrown by the user-supplied provider so `TokenCache` and `AuthHTTPError.isRetryable`
/// can classify them consistently:
/// - `CancellationError` is rethrown directly without wrapping so task cancellation is not mistaken for a provider failure.
/// - `CredentialsError.cannotFetchToken` is rethrown as-is to avoid double-wrapping.
/// - Any other error is wrapped in `CredentialsError.cannotFetchToken(message:underlyingError:)`, which `AuthHTTPError.isRetryable`
///   unwraps to inspect the underlying error (treating unknown third-party errors as transient and retryable by default, while
///   treating `CredentialsError.parseError`, `.notSupported`, and `.cannotLoadFile` as permanent).
struct CustomAccessTokenProviderAdapter: TokenProvider, Sendable {
  let provider: any AccessTokenProvider

  init(provider: any AccessTokenProvider) {
    self.provider = provider
  }

  @concurrent
  func fetchToken() async throws -> Token {
    let accessToken: AccessToken
    do {
      accessToken = try await provider.accessToken()
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as CredentialsError {
      if case .cannotFetchToken = error {
        throw error
      }
      throw CredentialsError.cannotFetchToken(
        message: "Could not fetch access token from custom provider.",
        underlyingError: error
      )
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not fetch access token from custom provider.",
        underlyingError: error
      )
    }

    return Token(
      accessToken: accessToken.token,
      tokenType: "Bearer",
      expirationDate: accessToken.expirationDate
    )
  }
}

/// An authentication provider backed by a custom ``AccessTokenProvider`` and managed by `TokenCache`.
struct AccessTokenProviderCredentials: CredentialsProvider, Sendable {
  private let cache: TokenCache<ContinuousClock>
  let quotaProjectID: String?
  let universeDomain: String?

  init(
    provider: any AccessTokenProvider,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    jitter: TokenCache<ContinuousClock>.JitterGenerator? = TokenCache<ContinuousClock>.defaultJitter
  ) {
    let adapter = CustomAccessTokenProviderAdapter(provider: provider)
    self.cache = TokenCache(
      provider: adapter,
      jitter: jitter,
      isRetryable: AuthHTTPError.isRetryable
    )
    self.quotaProjectID = quotaProjectID
    self.universeDomain = universeDomain
  }

  func accessToken() async throws -> AccessToken {
    return try await self.cache.token().asAccessToken
  }

  func headers() async throws -> AuthHeaders {
    let token = try await self.cache.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let quotaProjectID = self.quotaProjectID {
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }
}
