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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A `TokenProvider` implementation that exchanges an OAuth 2.0 refresh token for an access token.
///
/// Implements the standard [OAuth 2.0 Refreshing an Access Token](https://datatracker.ietf.org/doc/html/rfc6749#section-6)
/// flow. Requests are sent as `POST` requests to `tokenURL` with `grant_type=refresh_token`.
///
/// - SeeAlso: [RFC 6749: OAuth 2.0 Authorization Framework](https://datatracker.ietf.org/doc/html/rfc6749)
struct UserAccountTokenProvider: TokenProvider {
  /// The underlying user account credential data containing the client ID, secret, and refresh token.
  let user: UserAccountData

  /// The list of OAuth 2.0 scopes requested for the access token.
  let scopes: [String]

  /// The OAuth 2.0 token endpoint URL.
  let tokenURL: URL

  /// The retry configuration controlling backoff and attempt limits for token refresh requests.
  let retryConfiguration: RetryConfiguration

  /// The HTTP client used to send the refresh request.
  let httpClient: AuthHTTPClient

  /// Fetches a fresh OAuth 2.0 access token by executing the refresh token grant.
  ///
  /// - Returns: A valid `Token` containing the access token string and expiration date.
  /// - Throws: `CredentialsError.cannotFetchToken` if the token endpoint cannot be reached or rejects the request.
  @concurrent
  func fetchToken() async throws -> Token {
    let scopesStr = scopes.isEmpty ? nil : scopes.joined(separator: " ")

    let requestBody = Oauth2RefreshRequest(
      grantType: "refresh_token",
      clientId: user.clientId,
      clientSecret: user.clientSecret,
      refreshToken: user.refreshToken,
      scopes: scopesStr
    )

    // Wrap active POST request in exponential backoff retry loop
    let response: Oauth2RefreshResponse
    do {
      response = try await RetryEngine.retry(
        configuration: retryConfiguration,
        isRetryable: AuthHTTPError.isRetryable
      ) {
        return try await httpClient.post(
          url: tokenURL,
          body: requestBody
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not refresh user access token.",
        underlyingError: error
      )
    }

    let expirationDate = Date().addingTimeInterval(Double(response.expiresIn ?? 3600))

    return Token(
      accessToken: response.accessToken,
      tokenType: response.tokenType,
      expirationDate: expirationDate
    )
  }
}

/// The JSON request body sent to an OAuth 2.0 token endpoint to refresh an access token.
///
/// Conforms to the standard refresh token request specification defined in
/// [RFC 6749 Section 6](https://datatracker.ietf.org/doc/html/rfc6749#section-6).
struct Oauth2RefreshRequest: Codable {
  /// The OAuth 2.0 grant type, always `"refresh_token"`.
  let grantType: String

  /// The client identifier issued to the client during registration.
  let clientId: String

  /// The client secret corresponding to `clientId`.
  let clientSecret: String

  /// The refresh token issued to the client.
  let refreshToken: String

  /// An optional space-delimited list of requested scopes.
  let scopes: String?
}

/// The JSON response body returned by an OAuth 2.0 token endpoint upon successful token refresh.
///
/// Conforms to the standard successful response specification defined in
/// [RFC 6749 Section 5.1](https://datatracker.ietf.org/doc/html/rfc6749#section-5.1).
struct Oauth2RefreshResponse: Codable {
  /// The access token issued by the authorization server.
  let accessToken: String

  /// The lifetime in seconds of the access token. Defaults to 3600 (1 hour) if omitted.
  let expiresIn: Int?

  /// The type of the token issued, typically `"Bearer"`.
  let tokenType: String
}
