// snippet.hide
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

// snippet.show
import Foundation
import GoogleAuth

// Credentials invokes accessToken() on each request, so network-backed providers
// should cache tokens and retry transient failures internally.
actor CustomTokenProvider: AccessTokenProvider {
  private var cached: AccessToken?

  func accessToken() async throws -> AccessToken {
    if let cached, let expiry = cached.expirationDate, expiry > Date().addingTimeInterval(60) {
      return cached
    }
    let fresh = AccessToken(
      token: "custom-access-token",
      expirationDate: Date().addingTimeInterval(3600)
    )
    cached = fresh
    return fresh
  }
}

func configureAccessTokenCredentials(rawToken: String) async throws {
  // Static access token with a quota project override:
  let staticConfig = AccessTokenConfig(token: rawToken).with {
    $0.quotaProjectID = "my-billing-project"
  }
  let staticCredentials = try Credentials(configuration: .accessToken(staticConfig))
  _ = try await staticCredentials.headers()

  // Custom asynchronous AccessTokenProvider:
  let providerConfig = AccessTokenConfig(provider: CustomTokenProvider()).with {
    $0.quotaProjectID = "my-billing-project"
  }
  let providerCredentials = try Credentials(configuration: .accessToken(providerConfig))
  _ = try await providerCredentials.headers()
}
// snippet.hide

@main
struct SnippetRunner {
  static func main() async throws {
    try await configureAccessTokenCredentials(rawToken: "[placeholder]")
  }
}
