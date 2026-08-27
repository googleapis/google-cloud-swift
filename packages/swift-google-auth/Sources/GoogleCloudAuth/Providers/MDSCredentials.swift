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

/// Creates credentials backed by the local GCP Compute Engine Metadata Service (MDS).
struct MDSCredentials: CredentialsProvider, Sendable {
  let provider: MDSAccessTokenProvider
  let cache: TokenCache<ContinuousClock>
  var quotaProjectID: String? { provider.quotaProjectID }

  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    scopes: [String]? = nil,
    retryConfiguration: RetryConfiguration? = nil,
    client: AuthHTTPClient = AuthHTTPClient(),
    fromADC: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let provider = MDSAccessTokenProvider(
      endpoint: endpoint,
      quotaProjectID: quotaProjectID,
      scopes: scopes,
      retryConfiguration: retryConfiguration,
      client: client,
      fromADC: fromADC,
      environment: environment
    )
    self.provider = provider

    self.cache = TokenCache(
      provider: provider,
      isRetryable: MDSAccessTokenProvider.isRetryable
    )
  }

  // MARK: - CredentialsProvider

  func headers() async throws -> [(String, String)] {
    let token = try await self.cache.token()
    var headers = [("Authorization", "Bearer \(token.accessToken)")]
    if let quota = self.provider.quotaProjectID {
      headers.append(("X-Goog-User-Project", quota))
    }
    return headers
  }

  /// Retrieves the universe domain string override.
  func universeDomain() async -> String? {
    return nil
  }
}
