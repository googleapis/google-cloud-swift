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
import GoogleAuth
import Testing

/// Public-only API tests verifying that `AccessTokenProvider`, `AccessToken`, `AccessTokenConfig`,
/// and `Credentials.accessToken()` can be mocked and wrapped by forwarding decorators using plain
/// `import GoogleAuth` (never `@testable import`).
@Suite struct AccessTokenProviderPublicAPITests {
  private struct MockAccessTokenProvider: AccessTokenProvider {
    let token: AccessToken

    func accessToken() async throws -> AccessToken {
      token
    }
  }

  private actor ForwardingAccessTokenProvider: AccessTokenProvider {
    private let inner: any AccessTokenProvider
    private(set) var callCount = 0

    init(wrapping inner: any AccessTokenProvider) {
      self.inner = inner
    }

    func accessToken() async throws -> AccessToken {
      callCount += 1
      return try await inner.accessToken()
    }
  }

  @Test func mockAndForwardingDecoratorThroughPublicAPI() async throws {
    let expiry = Date().addingTimeInterval(3600)
    let expected = AccessToken(token: "mock-token.public-api", expirationDate: expiry)
    let mock = MockAccessTokenProvider(token: expected)
    let decorator = ForwardingAccessTokenProvider(wrapping: mock)

    let config = AccessTokenConfig(provider: decorator).with {
      $0.quotaProjectID = "public-quota-project"
      $0.universeDomain = "public.universe.com"
    }
    let credentials = try Credentials(configuration: .accessToken(config))

    let extracted = try await credentials.accessToken()
    #expect(extracted == expected)
    #expect(await decorator.callCount == 1)

    let headers = try await credentials.headers()
    #expect(
      headers == [
        ("Authorization", "Bearer mock-token.public-api"),
        ("x-goog-user-project", "public-quota-project"),
      ]
    )
    #expect(await decorator.callCount == 2)
    #expect(try await credentials.universeDomain() == "public.universe.com")

    let staticConfig = AccessTokenConfig(credentialSource: .staticToken(extracted)).with {
      $0.quotaProjectID = "static-quota-project"
    }
    let staticCredentials = try Credentials(configuration: .accessToken(staticConfig))
    #expect(try await staticCredentials.accessToken() == expected)
  }
}
