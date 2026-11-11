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
import Testing

@_spi(GoogleCloudInternal) @testable import GoogleAuth

private struct DummySubjectTokenProvider: SubjectTokenProvider {
  func subjectToken() async throws -> String { "subject-token" }
}

@Suite struct AuthMetricsTests {
  @Test func swiftAndAuthVersionPrefix() {
    let prefix = AuthMetrics.languageAndAuthVersion()
    let semver =
      #/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9a-zA-Z.-]+)?(?:\+[0-9a-zA-Z.-]+)?$/#
    #expect(AuthMetrics.swiftRuntimeVersion.wholeMatch(of: semver) != nil)
    #expect(!AuthMetrics.authPackageVersion.isEmpty)
    #expect(
      prefix == "gl-swift/\(AuthMetrics.swiftRuntimeVersion) auth/\(PackageVersion.version)"
    )
  }

  @Test(arguments: [
    (
      AuthRequestType.accessToken as AuthRequestType?,
      CredentialTypeMetrics.user as CredentialTypeMetrics?,
      "auth-request-type/at cred-type/u"
    ),
    (.accessToken, .serviceAccountAssertion, "auth-request-type/at cred-type/sa"),
    (.accessToken, .serviceAccountJWT, "auth-request-type/at cred-type/jwt"),
    (.accessToken, .mds, "auth-request-type/at cred-type/mds"),
    (.accessToken, .impersonated, "auth-request-type/at cred-type/imp"),
    (.idToken, .mds, "auth-request-type/it cred-type/mds"),
    (.idToken, .impersonated, "auth-request-type/it cred-type/imp"),
    (.mdsPing, nil, "auth-request-type/mds"),
    (nil, .user, "cred-type/u"),
    (nil, nil, ""),
  ])
  func tokenRequestHeaderFormatting(
    requestType: AuthRequestType?,
    credentialType: CredentialTypeMetrics?,
    expectedSuffix: String
  ) {
    let got = AuthMetrics.tokenRequestHeader(
      requestType: requestType,
      credentialType: credentialType
    )
    let prefix = AuthMetrics.languageAndAuthVersion()
    let expected = expectedSuffix.isEmpty ? prefix : "\(prefix) \(expectedSuffix)"
    #expect(got == expected)
  }

  @Test(arguments: [
    (
      BYOIDSource.programmatic, false, false,
      "google-byoid-sdk source/programmatic sa-impersonation/false config-lifetime/false"
    ),
    (
      .programmatic, true, false,
      "google-byoid-sdk source/programmatic sa-impersonation/true config-lifetime/false"
    ),
    (
      .programmatic, true, true,
      "google-byoid-sdk source/programmatic sa-impersonation/true config-lifetime/true"
    ),
  ])
  func byoidHeaderFormatting(
    source: BYOIDSource,
    saImpersonation: Bool,
    configLifetime: Bool,
    expectedSuffix: String
  ) {
    let got = AuthMetrics.byoidHeader(
      source: source,
      saImpersonation: saImpersonation,
      configLifetime: configLifetime
    )
    #expect(got == "\(AuthMetrics.languageAndAuthVersion()) \(expectedSuffix)")
  }

  @Test func credentialTypeAcrossConfigurations() async throws {
    let serviceAccountJSON = Data(
      """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
        "client_email": "test@project.iam.gserviceaccount.com"
      }
      """.utf8
    )
    let userJSON = Data(
      """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
      }
      """.utf8
    )

    let saCredentials = try Credentials(
      configuration: .serviceAccount(keyJSON: serviceAccountJSON)
    )
    #expect(saCredentials._credentialType == "jwt")
    let saHeaders = try await saCredentials.headers()
    #expect(!saHeaders.contains(name: AuthMetrics.headerName))

    let userCredentials = try Credentials(
      configuration: .user(keyJSON: userJSON)
    )
    #expect(userCredentials._credentialType == "u")

    let mdsCredentials = try Credentials(
      configuration: .mds(),
      environment: [:]
    )
    #expect(mdsCredentials._credentialType == "mds")

    let tempHome = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempHome) }

    let adcMDSCredentials = try Credentials(
      configuration: .adc(),
      environment: ["HOME": tempHome.path]
    )
    #expect(adcMDSCredentials._credentialType == "mds")

    let impersonatedConfig = ImpersonatedServiceAccountConfig(
      sourceCredentials: saCredentials,
      targetPrincipal: "target@project.iam.gserviceaccount.com"
    )
    let impersonatedCredentials = try Credentials(
      configuration: .impersonatedServiceAccount(impersonatedConfig)
    )
    #expect(impersonatedCredentials._credentialType == "imp")

    let externalConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: DummySubjectTokenProvider()),
      audience:
        "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/p/providers/prov",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let externalCredentials = try Credentials(
      configuration: .externalAccount(externalConfig)
    )
    #expect(externalCredentials._credentialType == nil)

    let apiKeyCredentials = try Credentials(configuration: .apiKey("test-api-key"))
    #expect(apiKeyCredentials._credentialType == nil)
    let apiKeyHeaders = try await apiKeyCredentials.headers()
    #expect(!apiKeyHeaders.contains(name: AuthMetrics.headerName))

    let anonymousCredentials = try Credentials(configuration: .anonymous)
    #expect(anonymousCredentials._credentialType == nil)
  }

  @Test func credentialTypeViaADCFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let saFile = tempDir.appendingPathComponent("sa.json")
    try Data(
      """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
        "client_email": "test@project.iam.gserviceaccount.com"
      }
      """.utf8
    ).write(to: saFile)
    let adcSA = try Credentials(
      configuration: .adc(),
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": saFile.path]
    )
    #expect(adcSA._credentialType == "jwt")

    let userFile = tempDir.appendingPathComponent("user.json")
    try Data(
      """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
      }
      """.utf8
    ).write(to: userFile)
    let adcUser = try Credentials(
      configuration: .adc(),
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": userFile.path]
    )
    #expect(adcUser._credentialType == "u")

    let impFile = tempDir.appendingPathComponent("impersonated.json")
    try Data(
      """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token"
        }
      }
      """.utf8
    ).write(to: impFile)
    let adcImp = try Credentials(
      configuration: .adc(),
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": impFile.path]
    )
    #expect(adcImp._credentialType == "imp")
  }
}
