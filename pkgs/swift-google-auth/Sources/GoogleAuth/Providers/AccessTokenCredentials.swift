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

/// An authentication provider backed by an ``AccessTokenProvider``.
struct AccessTokenCredentials: CredentialsProvider, AccessTokenProvider, Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  private let provider: any AccessTokenProvider
  let quotaProjectID: String?
  let universeDomain: String

  init(config: AccessTokenConfig) {
    self.provider = config.provider
    self.quotaProjectID = nonEmpty(config.quotaProjectID)
    self.universeDomain = nonEmpty(config.universeDomain) ?? defaultUniverseDomain
  }

  func accessToken() async throws -> AccessToken {
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

  func headers() async throws -> AuthHeaders {
    let validToken = try await self.accessToken()
    var headers: AuthHeaders = [("Authorization", "\(validToken.tokenType) \(validToken.token)")]
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
    let quotaDescription = quotaProjectID.map(String.init(reflecting:)) ?? "nil"
    return
      "AccessTokenCredentials(provider: AccessTokenProvider, quotaProjectID: \(quotaDescription), universeDomain: \(String(reflecting: universeDomain)))"
  }
}
