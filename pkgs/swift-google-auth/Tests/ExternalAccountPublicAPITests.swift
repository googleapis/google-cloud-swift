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

/// Public-only API tests verifying that `ExternalAccountConfig` and `SubjectTokenProvider`
/// can be configured, mutated, mocked, and wrapped by forwarding decorators using plain
/// `import GoogleAuth` (never `@testable import`).
@Suite struct ExternalAccountPublicAPITests {
  private struct MockSubjectTokenProvider: SubjectTokenProvider {
    let token: String

    func subjectToken() async throws -> String {
      token
    }
  }

  private actor ForwardingSubjectTokenProvider: SubjectTokenProvider {
    private let inner: any SubjectTokenProvider
    private(set) var callCount = 0

    init(wrapping inner: any SubjectTokenProvider) {
      self.inner = inner
    }

    func subjectToken() async throws -> String {
      callCount += 1
      return try await inner.subjectToken()
    }
  }

  @Test func mockAndForwardingDecoratorWithPublicTokenURLConfiguration() async throws {
    let mock = MockSubjectTokenProvider(token: "decorated-subject-token")
    let decorator = ForwardingSubjectTokenProvider(wrapping: mock)

    #expect(try await decorator.subjectToken() == "decorated-subject-token")
    #expect(await decorator.callCount == 1)

    let regionalURL = try #require(
      URL(string: "https://sts.us-central1.rep.googleapis.com/v1/token")
    )
    var config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: decorator),
      audience:
        "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/providers/prov",
      subjectTokenType: .idToken
    )
    #expect(config.tokenURL == nil)

    config.tokenURL = regionalURL
    #expect(config.tokenURL == regionalURL)

    let clearedConfig = config.with {
      $0.tokenURL = nil
      $0.universeDomain = "apis-tpclp.goog"
    }
    #expect(clearedConfig.tokenURL == nil)

    let credentials = try Credentials(configuration: .externalAccount(clearedConfig))
    #expect(credentials.accessTokenProvider != nil)
    #expect(try await credentials.universeDomain() == "apis-tpclp.goog")
  }
}
