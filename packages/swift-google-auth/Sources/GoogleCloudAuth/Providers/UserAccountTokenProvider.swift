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

// MARK: - TokenProvider

struct UserAccountTokenProvider: TokenProvider {
  let user: UserAccountData
  let scopes: [String]?
  let tokenUri: URL
  let retryConfiguration: RetryConfiguration
  let httpClient: AuthHTTPClient

  func fetchToken() async throws -> Token {
    let scopesStr = scopes?.joined(separator: " ")

    let requestBody = Oauth2RefreshRequest(
      grantType: "refresh_token",
      clientId: user.clientId,
      clientSecret: user.clientSecret,
      refreshToken: user.refreshToken,
      scopes: scopesStr
    )

    // Wrap active POST request in exponential backoff retry loop
    let response: Oauth2RefreshResponse = try await RetryEngine.retry(
      configuration: retryConfiguration,
      isRetryable: { error in
        return Self.isRetryable(error)
      }
    ) {
      return try await httpClient.post(
        url: tokenUri,
        body: requestBody
      )
    }

    let expirationDate = Date().addingTimeInterval(Double(response.expiresIn ?? 3600))

    return Token(
      accessToken: response.accessToken,
      tokenType: response.tokenType,
      expirationDate: expirationDate
    )
  }

  static func isRetryable(_ error: Error) -> Bool {
    if let authError = error as? AuthHTTPError, let status = authError.statusCode {
      return status >= 500 || status == 429 || status == 408
    }
    return true
  }
}

// MARK: - Request & Response DTOs

struct Oauth2RefreshRequest: Codable {
  let grantType: String
  let clientId: String
  let clientSecret: String
  let refreshToken: String
  let scopes: String?
}

struct Oauth2RefreshResponse: Codable {
  let accessToken: String
  let expiresIn: Int?
  let tokenType: String
}
