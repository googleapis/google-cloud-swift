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

/// An authentication provider backed by either a static ``AccessToken`` or a custom ``AccessTokenProvider``.
struct AccessTokenCredentials: CredentialsProvider, AccessTokenProvider, Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Error thrown as the underlying error when a static access token has expired.
  private struct ExpiredTokenError: Error, Sendable, CustomStringConvertible {
    let expirationDate: Date

    var description: String {
      "Static access token expired at \(expirationDate)."
    }
  }

  private let credentialSource: AccessTokenConfig.CredentialSource
  private let timeSource: any TimeSource
  let quotaProjectID: String?
  let universeDomain: String

  init(
    config: AccessTokenConfig,
    timeSource: any TimeSource = SystemTimeSource()
  ) {
    self.credentialSource = config.credentialSource
    self.timeSource = timeSource
    self.quotaProjectID = nonEmpty(config.quotaProjectID)
    self.universeDomain = nonEmpty(config.universeDomain) ?? defaultUniverseDomain
  }

  func accessToken() async throws -> AccessToken {
    switch self.credentialSource {
    case let .staticToken(token):
      // Evaluate against exact wall-clock time (`<= now`) without refresh slack because static tokens
      // cannot be refreshed early, and applying a refresh margin would prematurely reject valid tokens.
      if let expirationDate = token.expirationDate, expirationDate <= self.timeSource.now {
        throw CredentialsError.cannotFetchToken(
          message: "The static access token has expired and cannot be refreshed.",
          underlyingError: ExpiredTokenError(expirationDate: expirationDate)
        )
      }
      return token
    case let .provider(provider):
      do {
        return try await provider.accessToken()
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as CredentialsError {
        throw error
      } catch {
        throw CredentialsError.cannotFetchToken(
          message: "Could not fetch access token from custom provider.",
          underlyingError: error
        )
      }
    }
  }

  func headers() async throws -> AuthHeaders {
    let validToken = try await self.accessToken()
    var headers: AuthHeaders = [("Authorization", "Bearer \(validToken.token)")]
    if let quotaProjectID = self.quotaProjectID {
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }

  func universeDomain() async throws -> String {
    return self.universeDomain
  }

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    switch self.credentialSource {
    case .staticToken:
      return
        "AccessTokenCredentials(token: \"[redacted]\", quotaProjectID: \(String(describing: quotaProjectID)), universeDomain: \(String(reflecting: universeDomain)))"
    case .provider:
      return
        "AccessTokenCredentials(provider: AccessTokenProvider, quotaProjectID: \(String(describing: quotaProjectID)), universeDomain: \(String(reflecting: universeDomain)))"
    }
  }
}
