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
import Testing
@testable import GoogleCloudAuth

private struct StaticSubjectTokenProvider: SubjectTokenProvider {
  let token: String

  func subjectToken() async throws -> String {
    return token
  }
}

private func integrationTestsEnabled() -> Bool {
  ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
}

@Suite(
  "External Account Google Cloud Live OIDC Integration Tests",
  .enabled(if: integrationTestsEnabled())
)
struct ExternalAccountGoogleCloudIntegrationTests {
  /// Generates a live OIDC ID token by calling the IAM Credentials REST API (generateIdToken)
  /// using ambient Application Default Credentials (ADC).
  ///
  /// This matches the pattern in google-cloud-rust (integration-auth generate_id_token).
  private func generateOIDCIDToken(audience: String, saEmail: String) async throws -> String {
    let adc = try ADC.resolve()
    let authHeaders = try await adc.headers()

    let endpoint =
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/\(saEmail):generateIdToken"
    guard let url = URL(string: endpoint) else {
      throw CredentialsError.parseError("Invalid URL for IAM generateIdToken: \(endpoint)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in authHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let requestBody: [String: Any] = [
      "audience": audience,
      "includeEmail": true,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CredentialsError.parseError("IAM generateIdToken did not return HTTPURLResponse")
    }

    guard httpResponse.statusCode == 200 else {
      let errBody = String(data: data, encoding: .utf8) ?? ""
      throw CredentialsError.parseError(
        "IAM generateIdToken failed with HTTP \(httpResponse.statusCode): \(errBody)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let token = json["token"] as? String, !token.isEmpty
    else {
      throw CredentialsError.parseError("Invalid response JSON from IAM generateIdToken")
    }

    return token
  }

  @Test("Generates IAM OIDC ID token, exchanges via STS, and verifies access token")
  func testProgrammaticGoogleCloudOIDCSTSExchange() async throws {
    guard let project = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"],
      let audience = ProcessInfo.processInfo.environment["GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"],
      !project.isEmpty
    else {
      print(
        "Skipping M1 test: Missing GOOGLE_CLOUD_PROJECT or GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"
      )
      return
    }

    // 1. Obtain OIDC ID token (via direct env var or dynamically via IAM Credentials REST API)
    let idToken: String
    if let envToken = ProcessInfo.processInfo.environment["EXTERNAL_ACCOUNT_SUBJECT_TOKEN"],
      !envToken.isEmpty
    {
      idToken = envToken
    } else if let saEmail = ProcessInfo.processInfo.environment[
      "EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL"
    ],
      !saEmail.isEmpty
    {
      idToken = try await generateOIDCIDToken(audience: audience, saEmail: saEmail)
    } else {
      print(
        "Skipping M1 test: Neither EXTERNAL_ACCOUNT_SUBJECT_TOKEN nor EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL set"
      )
      return
    }

    // 2. Configure Programmatic External Account Credentials
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )

    // 3. Request auth headers (triggers real STS token exchange)
    let headers = try await creds.headers()
    let authHeader = headers.first(where: { $0.0.lowercased() == "authorization" })

    #expect(authHeader != nil)
    #expect(authHeader?.1.hasPrefix("Bearer ya29.") == true)

    // 4. Also verify public Credentials API wrapper
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let publicCredentials = try Credentials(configuration: .programmaticExternalAccount(config))
    let publicHeaders = try await publicCredentials.headers()
    let publicAuthHeader = publicHeaders.first(where: { $0.0.lowercased() == "authorization" })

    #expect(publicAuthHeader != nil)
    #expect(publicAuthHeader?.1.hasPrefix("Bearer ya29.") == true)
  }

  @Test("Exchanges Apple ID token and calls BigQuery list datasets end-to-end")
  func testAppleIDEndToEndBigQueryListDatasets() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let project = env["GOOGLE_CLOUD_PROJECT"],
      let audience = env["APPLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE"],
      let idToken = env["APPLE_ID_TOKEN"],
      !project.isEmpty, !audience.isEmpty, !idToken.isEmpty
    else {
      print(
        "Skipping Apple ID E2E test: Missing GOOGLE_CLOUD_PROJECT, APPLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE, or APPLE_ID_TOKEN"
      )
      return
    }

    // 1. Configure Programmatic External Account Credentials
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: StaticSubjectTokenProvider(token: idToken)
      ),
      audience: audience,
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let credentials = try Credentials(configuration: .programmaticExternalAccount(config))

    // 2. Obtain auth headers (STS exchange)
    let headers = try await credentials.headers()
    let authHeader = headers.first(where: { $0.0.lowercased() == "authorization" })
    #expect(authHeader != nil)
    #expect(authHeader?.1.hasPrefix("Bearer ya29.") == true)

    // 3. Call Google BigQuery REST API with the exchanged access token
    let endpoint = "https://bigquery.googleapis.com/bigquery/v2/projects/\(project)/datasets"
    guard let url = URL(string: endpoint) else {
      throw CredentialsError.parseError("Invalid BigQuery endpoint: \(endpoint)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CredentialsError.parseError("BigQuery did not return HTTPURLResponse")
    }

    guard httpResponse.statusCode == 200 else {
      let errBody = String(data: data, encoding: .utf8) ?? ""
      throw CredentialsError.parseError(
        "BigQuery list datasets failed with HTTP \(httpResponse.statusCode): \(errBody)")
    }

    #expect(httpResponse.statusCode == 200)
  }
}
