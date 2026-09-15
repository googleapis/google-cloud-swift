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
import GoogleCloudAuth
import GoogleIAMCredentialsV1
import Testing

private struct StaticSubjectTokenProvider: SubjectTokenProvider {
  let token: String

  func subjectToken() async throws -> String {
    token
  }
}

private func googleOIDCIntegrationEnabled() -> Bool {
  let env = ProcessInfo.processInfo.environment
  return env["GOOGLE_CLOUD_PROJECT"] != nil
    && env["GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"] != nil
    && (env["EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL"] != nil
      || env["EXTERNAL_ACCOUNT_SUBJECT_TOKEN"] != nil)
}

private func appleIDIntegrationEnabled() -> Bool {
  let env = ProcessInfo.processInfo.environment
  return env["GOOGLE_CLOUD_PROJECT"] != nil
    && env["APPLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"] != nil
    && env["APPLE_ID_TOKEN"] != nil
}

@Suite("External Account (BYOID) Integration Tests")
struct ExternalAccountIntegrationTests {
  @Test(
    "Exchanges Google OIDC token via STS and verifies access token",
    .enabled(if: googleOIDCIntegrationEnabled())
  )
  func testGoogleOIDCWorkloadIdentityFederation() async throws {
    let env = ProcessInfo.processInfo.environment
    let audience = env["GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"]!

    let idToken: String
    if let staticToken = env["EXTERNAL_ACCOUNT_SUBJECT_TOKEN"], !staticToken.isEmpty {
      idToken = staticToken
    } else {
      let saEmail = env["EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL"]!
      let iamClient = try IAMCredentialsClient()
      let response = try await iamClient.generateIdToken(
        request: GenerateIdTokenRequest().with {
          $0.name = "projects/-/serviceAccounts/\(saEmail)"
          $0.audience = audience
        }
      )
      idToken = response.token
    }

    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let credentials = try Credentials(configuration: .programmaticExternalAccount(config))

    let headers = try await credentials.headers()
    let authHeader = headers.first(where: { $0.0.lowercased() == "authorization" })
    #expect(authHeader != nil)
    #expect(authHeader?.1.hasPrefix("Bearer ya29.") == true)
  }

  @Test(
    "Exchanges Apple ID token via STS and verifies access token",
    .enabled(if: appleIDIntegrationEnabled())
  )
  func testAppleIDWorkloadIdentityFederation() async throws {
    let env = ProcessInfo.processInfo.environment
    let audience = env["APPLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"]!
    let idToken = env["APPLE_ID_TOKEN"]!

    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let credentials = try Credentials(configuration: .programmaticExternalAccount(config))

    let headers = try await credentials.headers()
    let authHeader = headers.first(where: { $0.0.lowercased() == "authorization" })
    #expect(authHeader != nil)
    #expect(authHeader?.1.hasPrefix("Bearer ya29.") == true)
  }
}
