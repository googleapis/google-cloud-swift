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

internal struct ServiceAccountParser: CredentialSourceParser {
  internal static let type = "service_account"

  internal init() {}

  internal func parse(
    config: [String: Any],
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider {
    let data = try JSONSerialization.data(withJSONObject: config, options: [])
    let accessSpecifier = scopes.isEmpty ? nil : AccessSpecifier.scopes(scopes)
    return try ServiceAccountCredentials(
      keyJSON: data,
      quotaProjectID: quotaProjectID,
      universeDomain: universeDomain,
      accessSpecifier: accessSpecifier
    )
  }
}

/// Creates credentials backed by a local Service Account JSON key file.
struct ServiceAccountCredentials: CredentialsProvider, Sendable {
  private let tokenProvider: TokenCache<ContinuousClock>
  private let quotaProjectID: String?
  private let universeDomain: String?

  init(
    keyJSON: Data,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    accessSpecifier: AccessSpecifier? = nil
  ) throws {
    let key: ServiceAccountData
    do {
      key = try JSONDecoder().decode(ServiceAccountData.self, from: keyJSON)
    } catch {
      throw CredentialsError.parseError(
        "Failed to parse Service Account key JSON: \(error.localizedDescription)")
    }
    let provider = ServiceAccountTokenProvider(key: key, accessSpecifier: accessSpecifier)

    self.tokenProvider = TokenCache(provider: provider)
    self.quotaProjectID = quotaProjectID
    self.universeDomain = universeDomain ?? key.universeDomain
  }

  func headers() async throws -> AuthHeaders {
    let token = try await tokenProvider.token()
    var headers: AuthHeaders = [("Authorization", "\(token.tokenType) \(token.accessToken)")]
    if let quotaProjectID = quotaProjectID {
      headers.append(("x-goog-user-project", quotaProjectID))
    }
    return headers
  }

  func universeDomain() async -> String? {
    return self.universeDomain
  }
}
