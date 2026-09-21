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

/// An authentication provider backed by a local Service Account JSON private key file.
///
/// A [Service Account](https://cloud.google.com/iam/docs/service-account-overview) is a Google Cloud identity
/// intended for non-human workloads, microservices, and applications.
///
/// Service account JSON key files contain an unencrypted RSA private key (`private_key`) that allows the bearer
/// to act as the service account. These files should be treated with the same security precautions as unencrypted
/// passwords and stored securely (e.g. in Google Cloud Secret Manager).
///
/// This provider uses the private key to sign a local JSON Web Signature (JWS) assertion using RS256
/// according to [AIP-4111](https://google.aip.dev/auth/4111). Tokens are cached and refreshed before expiration
/// without requiring remote authorization server calls.
///
/// See [Best Practices for Managing Service Account Keys](https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)
/// and [AIP-4111: Self-Signed JWTs](https://google.aip.dev/auth/4111).
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
      headers.append(name: "x-goog-user-project", value: quotaProjectID)
    }
    return headers
  }

  func universeDomain() async -> String? {
    return self.universeDomain
  }
}
