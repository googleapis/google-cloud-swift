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
import GoogleWKT

/// A `TokenProvider` that exchanges a source credential's authentication headers for a short-lived
/// OAuth 2.0 access token impersonating a target Google Cloud service account.
///
/// Calls the IAM Service Account Credentials API endpoint:
/// `POST https://iamcredentials.{universeDomain}/v1/projects/-/serviceAccounts/{targetPrincipal}:generateAccessToken`
///
/// - SeeAlso: [AIP-4110: Application Default Credentials](https://google.aip.dev/auth/4110)
/// - SeeAlso: [Method: projects.serviceAccounts.generateAccessToken](https://cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/generateAccessToken)
struct ImpersonatedTokenProvider: TokenProvider, Sendable {
  /// The underlying source credentials used to authenticate the IAM `:generateAccessToken` request.
  let sourceCredentials: any CredentialsProvider

  /// The full IAM Credentials `:generateAccessToken` endpoint URL.
  let iamEndpointURL: URL

  /// The OAuth 2.0 scopes requested for the impersonated access token.
  let scopes: [String]

  /// Normalized service account resource names (`projects/-/serviceAccounts/{email}`) in the delegation chain.
  let delegates: [String]

  /// Desired lifetime of the impersonated access token.
  let lifetime: WKTDuration

  /// Retry policy configuration for transient IAM API errors.
  let retryConfiguration: RetryConfiguration

  /// HTTP client used to execute the `:generateAccessToken` request.
  let httpClient: AuthHTTPClient

  @concurrent
  func fetchToken() async throws -> Token {
    let sourceAuthHeaders: AuthHeaders
    do {
      sourceAuthHeaders = try await sourceCredentials.headers()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not obtain source credentials token for service account impersonation.",
        underlyingError: error
      )
    }

    var headersDict: [String: String] = [:]
    for (name, value) in sourceAuthHeaders {
      headersDict[name] = value
    }
    let requestHeaders = headersDict

    let requestBody = IAMGenerateAccessTokenRequest(
      scope: scopes,
      delegates: delegates.isEmpty ? nil : delegates,
      lifetime: lifetime
    )

    let response: IAMGenerateAccessTokenResponse
    do {
      response = try await RetryEngine.retry(
        configuration: retryConfiguration,
        isRetryable: AuthHTTPError.isRetryable
      ) {
        try await httpClient.post(
          url: iamEndpointURL,
          body: requestBody,
          headers: requestHeaders
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: "Could not generate impersonated service account access token.",
        underlyingError: error
      )
    }

    return Token(
      accessToken: response.accessToken,
      tokenType: "Bearer",
      expirationDate: response.expireTime.date
    )
  }
}
