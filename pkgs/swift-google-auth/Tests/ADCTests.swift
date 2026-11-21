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
@testable import GoogleAuth

@Suite struct ADCTest {
  @Test func resolvesToMDSCredentials() async throws {
    let provider = try ADC.resolve(environment: [:])
    #expect(provider is MDSCredentials)
  }

  @Test(arguments: ["true", "TRUE", "True", "1", " true ", "\tTRUE\n"])
  func noGCECheckSkipsMDSFallbackAndThrowsCredentialsNotFound(value: String) throws {
    let tempHome = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempHome) }

    for environment in [
      ["NO_GCE_CHECK": value],
      ["NO_GCE_CHECK": value, "HOME": tempHome.path, "APPDATA": tempHome.path],
      ["NO_GCE_CHECK": value, "GCE_METADATA_HOST": ""],
    ] {
      let error = #expect(throws: CredentialsError.self) {
        _ = try ADC.resolve(environment: environment)
      }
      guard case let .credentialsNotFound(message) = error else {
        Issue.record(
          "Expected CredentialsError.credentialsNotFound, got \(String(describing: error))")
        return
      }
      #expect(message.contains("NO_GCE_CHECK"))
      #expect(message.contains("gcloud auth application-default login"))
      #expect(message.contains("GOOGLE_APPLICATION_CREDENTIALS"))
    }
  }

  @Test(arguments: ["false", "FALSE", "0", "", "no", "2"])
  func falsyNoGCECheckStillFallsBackToMDS(value: String) throws {
    let provider = try ADC.resolve(environment: ["NO_GCE_CHECK": value])
    #expect(provider is MDSCredentials)
  }

  @Test func noGCECheckTakesPrecedenceOverExplicitMetadataHost() throws {
    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(
        environment: [
          "NO_GCE_CHECK": "true",
          "GCE_METADATA_HOST": "127.0.0.1:8080",
        ]
      )
    }
    guard case let .credentialsNotFound(message) = error else {
      Issue.record(
        "Expected CredentialsError.credentialsNotFound, got \(String(describing: error))")
      return
    }
    #expect(message.contains("NO_GCE_CHECK"))
  }

  @Test func noGCECheckDoesNotAffectExplicitCredentialsFile() throws {
    let json = """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "NO_GCE_CHECK": "true",
      ]
    )
    #expect(provider is UserCredentials)
  }

  @Test func noGCECheckDoesNotAffectWellKnownCredentialsFile() throws {
    let json = """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
      }
      """
    let tempHome = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempHome) }

    let posixDir = tempHome.appendingPathComponent(".config/gcloud", isDirectory: true)
    let windowsDir = tempHome.appendingPathComponent("gcloud", isDirectory: true)
    try FileManager.default.createDirectory(at: posixDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: windowsDir, withIntermediateDirectories: true)
    try Data(json.utf8).write(
      to: posixDir.appendingPathComponent("application_default_credentials.json"))
    try Data(json.utf8).write(
      to: windowsDir.appendingPathComponent("application_default_credentials.json"))

    let provider = try ADC.resolve(
      environment: [
        "HOME": tempHome.path,
        "APPDATA": tempHome.path,
        "NO_GCE_CHECK": "true",
      ]
    )
    #expect(provider is UserCredentials)
  }

  @Test func propagatesEnvironmentToMDS() async throws {
    let customHost = "custom-metadata.local"
    let environment = ["GCE_METADATA_HOST": customHost]
    let provider = try ADC.resolve(environment: environment)

    guard let mdsCreds = provider as? MDSCredentials else {
      Issue.record("Expected MDSCredentials")
      return
    }

    #expect(mdsCreds.provider.environment["GCE_METADATA_HOST"] == customHost)
  }

  @Test func propagatesScopesToMDS() async throws {
    let customScopes = ["scope1", "scope2"]
    let provider = try ADC.resolve(scopes: customScopes, environment: [:])

    guard let mdsCreds = provider as? MDSCredentials else {
      Issue.record("Expected MDSCredentials")
      return
    }

    #expect(mdsCreds.provider.scopes == customScopes)
  }

  @Test func resolvesServiceAccountFromFile() async throws {
    let json = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
        "client_email": "test@gserviceaccount.com"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    #expect(provider is ServiceAccountCredentials)
  }

  @Test func resolvesServiceAccountQuotaProjectPrecedence() async throws {
    let json = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
        "client_email": "test@gserviceaccount.com",
        "quota_project_id": "json-quota-project"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let fromJSON = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    let fromJSONHeaders = try await fromJSON.headers()
    #expect(fromJSONHeaders.values(for: "x-goog-user-project") == ["json-quota-project"])

    let fromParameter = try ADC.resolve(
      quotaProjectID: "config-quota-project",
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    let fromParameterHeaders = try await fromParameter.headers()
    #expect(fromParameterHeaders.values(for: "x-goog-user-project") == ["config-quota-project"])

    let fromEnv = try ADC.resolve(
      quotaProjectID: "config-quota-project",
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_QUOTA_PROJECT": "env-quota-project",
      ]
    )
    let fromEnvHeaders = try await fromEnv.headers()
    #expect(fromEnvHeaders.values(for: "x-goog-user-project") == ["env-quota-project"])

    let fromEmptyEnvWithParameter = try ADC.resolve(
      quotaProjectID: "config-quota-project",
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_QUOTA_PROJECT": "",
      ]
    )
    let fromEmptyEnvWithParameterHeaders = try await fromEmptyEnvWithParameter.headers()
    #expect(
      fromEmptyEnvWithParameterHeaders.values(for: "x-goog-user-project")
        == ["config-quota-project"]
    )

    let fromEmptyEnvAndEmptyParameter = try ADC.resolve(
      quotaProjectID: "",
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_QUOTA_PROJECT": "",
      ]
    )
    let fromEmptyEnvAndEmptyParameterHeaders = try await fromEmptyEnvAndEmptyParameter.headers()
    #expect(
      fromEmptyEnvAndEmptyParameterHeaders.values(for: "x-goog-user-project")
        == ["json-quota-project"]
    )
  }

  @Test func resolvesUserCredentialsFromFile() async throws {
    let json = """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    #expect(provider is UserCredentials)
  }

  @Test func resolvesUserCredentialsQuotaProjectPrecedence() throws {
    let jsonWithQuota = """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "quota_project_id": "json-quota-project"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(jsonWithQuota.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let fromJSON = try #require(
      try ADC.resolve(
        environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
      ) as? UserCredentials)
    #expect(fromJSON.quotaProjectID == "json-quota-project")

    let fromParameter = try #require(
      try ADC.resolve(
        quotaProjectID: "config-quota-project",
        environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
      ) as? UserCredentials)
    #expect(fromParameter.quotaProjectID == "config-quota-project")

    let fromEnv = try #require(
      try ADC.resolve(
        quotaProjectID: "config-quota-project",
        environment: [
          "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
          "GOOGLE_CLOUD_QUOTA_PROJECT": "env-quota-project",
        ]
      ) as? UserCredentials)
    #expect(fromEnv.quotaProjectID == "env-quota-project")

    let fromEmptyEnvWithParameter = try #require(
      try ADC.resolve(
        quotaProjectID: "config-quota-project",
        environment: [
          "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
          "GOOGLE_CLOUD_QUOTA_PROJECT": "",
        ]
      ) as? UserCredentials)
    #expect(fromEmptyEnvWithParameter.quotaProjectID == "config-quota-project")

    let fromEmptyEnvAndEmptyParameter = try #require(
      try ADC.resolve(
        quotaProjectID: "",
        environment: [
          "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
          "GOOGLE_CLOUD_QUOTA_PROJECT": "",
        ]
      ) as? UserCredentials)
    #expect(fromEmptyEnvAndEmptyParameter.quotaProjectID == "json-quota-project")

    let jsonWithEmptyQuota = """
      {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "quota_project_id": ""
      }
      """
    let emptyQuotaFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(jsonWithEmptyQuota.utf8).write(to: emptyQuotaFile)
    defer { try? FileManager.default.removeItem(at: emptyQuotaFile) }

    let fromAllEmpty = try #require(
      try ADC.resolve(
        quotaProjectID: "",
        environment: [
          "GOOGLE_APPLICATION_CREDENTIALS": emptyQuotaFile.path,
          "GOOGLE_CLOUD_QUOTA_PROJECT": "",
        ]
      ) as? UserCredentials)
    #expect(fromAllEmpty.quotaProjectID == nil)
  }

  @Test func throwsParseErrorOnMissingType() throws {
    let json = """
      {
        "project_id": "test-project-id"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
  }

  @Test func throwsNotSupportedOnUnknownType() throws {
    let json = """
      {
        "type": "unknown_credential_type"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .notSupported(message) = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
    #expect(message.contains("unknown_credential_type"))
  }

  @Test func resolvesImpersonatedServiceAccountWithAuthorizedUserSourceFromFile() async throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "delegates": [
          "projects/-/serviceAccounts/delegate1@project.iam.gserviceaccount.com",
          "delegate2@project.iam.gserviceaccount.com"
        ],
        "quota_project_id": "json-quota-project",
        "source_credentials": {
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      scopes: ["https://www.googleapis.com/auth/devstorage.read_write"],
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    guard let impersonated = provider as? ImpersonatedCredentials else {
      Issue.record("Expected ImpersonatedCredentials, got \(type(of: provider))")
      return
    }
    #expect(impersonated.quotaProjectID == "json-quota-project")
    #expect(try await impersonated.universeDomain() == "googleapis.com")
    #expect(
      impersonated.provider.iamEndpointURL.absoluteString
        == "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
    )
    #expect(
      impersonated.provider.delegates == [
        "projects/-/serviceAccounts/delegate1@project.iam.gserviceaccount.com",
        "projects/-/serviceAccounts/delegate2@project.iam.gserviceaccount.com",
      ]
    )
    #expect(
      impersonated.provider.scopes == ["https://www.googleapis.com/auth/devstorage.read_write"]
    )
    #expect(impersonated.provider.sourceCredentials is UserCredentials)
  }

  @Test func resolvesImpersonatedServiceAccountWithServiceAccountSourceFromFile() async throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "universe_domain": "my-universe.com",
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com",
          "quota_project_id": "source-quota-proj"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      quotaProjectID: "explicit-quota-proj",
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_QUOTA_PROJECT": "env-quota-proj",
      ]
    )
    guard let impersonated = provider as? ImpersonatedCredentials else {
      Issue.record("Expected ImpersonatedCredentials, got \(type(of: provider))")
      return
    }
    #expect(impersonated.quotaProjectID == "env-quota-proj")
    #expect(try await impersonated.universeDomain() == "my-universe.com")
    #expect(impersonated.provider.sourceCredentials is ServiceAccountCredentials)
    let sourceHeaders = try await impersonated.provider.sourceCredentials.headers()
    #expect(sourceHeaders["Authorization"]?.hasPrefix("Bearer ") == true)
    #expect(sourceHeaders.values(for: "x-goog-user-project") == ["source-quota-proj"])

    let noOuterQuotaProvider = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    let noOuterQuotaImpersonated = try #require(noOuterQuotaProvider as? ImpersonatedCredentials)
    #expect(noOuterQuotaImpersonated.quotaProjectID == nil)
    let noOuterSourceHeaders = try await noOuterQuotaImpersonated.provider.sourceCredentials
      .headers()
    #expect(noOuterSourceHeaders.values(for: "x-goog-user-project") == ["source-quota-proj"])
  }

  @Test func normalizesEmptyUniverseDomainAndQuotaProjectInImpersonatedADC() async throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "quota_project_id": "",
        "universe_domain": "",
        "source_credentials": {
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token",
          "quota_project_id": ""
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      quotaProjectID: "",
      universeDomain: "",
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    guard let impersonated = provider as? ImpersonatedCredentials else {
      Issue.record("Expected ImpersonatedCredentials, got \(type(of: provider))")
      return
    }
    #expect(impersonated.quotaProjectID == nil)
    let sourceUser = try #require(impersonated.provider.sourceCredentials as? UserCredentials)
    #expect(sourceUser.quotaProjectID == nil)
    #expect(try await impersonated.universeDomain() == "googleapis.com")
  }

  @Test func resolvesNestedImpersonatedServiceAccountInSourceCredentials() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "type": "impersonated_service_account",
          "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/inner@project.iam.gserviceaccount.com:generateAccessToken",
          "source_credentials": {
            "type": "authorized_user",
            "client_id": "test-client-id",
            "client_secret": "test-client-secret",
            "refresh_token": "test-refresh-token"
          }
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    guard let outer = provider as? ImpersonatedCredentials else {
      Issue.record("Expected outer ImpersonatedCredentials, got \(type(of: provider))")
      return
    }
    guard let inner = outer.provider.sourceCredentials as? ImpersonatedCredentials else {
      Issue.record(
        "Expected inner ImpersonatedCredentials, got \(type(of: outer.provider.sourceCredentials))"
      )
      return
    }
    #expect(inner.provider.sourceCredentials is UserCredentials)
  }

  @Test func rejectsUnsupportedSourceCredentialsTypeInImpersonatedADC() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "type": "unknown_source_type"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .notSupported(message) = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
    #expect(message.contains("unknown_source_type"))
  }

  @Test func rejectsMissingOrInvalidTypeInImpersonatedSourceCredentials() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "client_id": "test-client-id"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .parseError(message) = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(message.contains("Missing or invalid 'type'"))
  }

  @Test func rejectsMalformedImpersonatedServiceAccountJSON() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": "not-an-object"
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .parseError(message) = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(message.contains("Failed to parse Impersonated Service Account key JSON"))
  }

  @Test func rejectsAuthorizedUserSourceCredentialsInCustomUniverseDomain() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "universe_domain": "my-universe.com",
        "source_credentials": {
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .notSupported(message) = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
    #expect(message.contains("my-universe.com"))
  }

  @Test func propagatesUniverseDomainToMDS() async throws {
    let provider = try ADC.resolve(universeDomain: "custom.universe.com", environment: [:])
    guard let mdsCreds = provider as? MDSCredentials else {
      Issue.record("Expected MDSCredentials")
      return
    }
    #expect(try await mdsCreds.universeDomain() == "custom.universe.com")
  }

  @Test func rejectsConflictingSourceUniverseDomainInImpersonatedADC() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.universe-b.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "universe_domain": "universe-b.com",
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com",
          "universe_domain": "universe-a.com"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case let .parseError(message) = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(message.contains("universe-a.com"))
    #expect(message.contains("universe-b.com"))

    let omittedOuterJSON = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com",
          "universe_domain": "universe-a.com"
        }
      }
      """
    try Data(omittedOuterJSON.utf8).write(to: tempFile)
    #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }

    let mismatchedURLHostJSON = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "universe_domain": "universe-a.com",
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com",
          "universe_domain": "universe-a.com"
        }
      }
      """
    try Data(mismatchedURLHostJSON.utf8).write(to: tempFile)
    #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
  }

  @Test(
    arguments: [
      "https://oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com:443/token",
      "HTTPS://OAUTH2.GOOGLEAPIS.COM/token",
      "https://oauth2.googleapis.com/token-override",
    ]
  )
  func acceptsValidTokenURIInAuthorizedUserADC(tokenURI: String) throws {
    let payload: [String: String] = [
      "type": "authorized_user",
      "client_id": "test-client-id",
      "client_secret": "test-client-secret",
      "refresh_token": "test-refresh-token",
      "token_uri": tokenURI,
    ]
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try JSONEncoder().encode(payload).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    let userCreds = try #require(provider as? UserCredentials)
    #expect(userCreds.provider.tokenURL.absoluteString == tokenURI)
  }

  @Test(
    arguments: [
      "http://oauth2.googleapis.com/token",
      "https://other.example.com/token",
      "https://oauth2.googleapis.com.other.example/token",
      "https://oauth2.googleapis.com./token",
      "https://169.254.169.254/token",
      "https://127.0.0.1/token",
      "unix:///tmp/sock",
      "http+unix://%2Ftmp%2Fsock/token",
      "https://oauth2.googleapis.com:8443/token",
      "https://user:pass@oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com/token?foo=bar",
      "https://oauth2.googleapis.com/token#frag",
      "https://oauth2.googleapis.com/./token",
      "https://oauth2.googleapis.com/%2e/token",
      "https://oauth2.googleapis.com/v1/../token",
      "https://oauth2.googleapis.com/%2e%2e/token",
      "https://oauth2.googleapis.com/v1/%2f..%2f/token",
      "https://oauth2.googleapis.com/%5ctoken",
      "https://oauth2.googleapis.com/\\token",
      " https://oauth2.googleapis.com/token",
      "https://oauth2.googleapis.com/token ",
      "   ",
      "",
    ]
  )
  func rejectsInvalidTokenURIInAuthorizedUserADC(tokenURI: String) throws {
    let payload: [String: String] = [
      "type": "authorized_user",
      "client_id": "test-client-id",
      "client_secret": "test-client-secret",
      "refresh_token": "test-refresh-token",
      "token_uri": tokenURI,
    ]
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try JSONEncoder().encode(payload).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
  }

  @Test(
    arguments: [
      (
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://IAMCREDENTIALS.GOOGLEAPIS.COM/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.us-central1.rep.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://us-central1-iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "my-universe.com"
      ),
      (
        "https://iamcredentials.europe-west1.rep.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "my-universe.com"
      ),
      (
        "https://europe-west1-iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "my-universe.com"
      ),
    ]
  )
  func acceptsValidImpersonatedServiceAccountURLsInADC(
    impersonationURL: String,
    universeDomain: String?
  ) async throws {
    let universeEntry = universeDomain.map { "\"universe_domain\": \"\($0)\"," } ?? ""
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "\(impersonationURL)",
        \(universeEntry)
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let provider = try ADC.resolve(
      environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    )
    let impersonated = try #require(provider as? ImpersonatedCredentials)
    #expect(impersonated.provider.iamEndpointURL.absoluteString == impersonationURL)
    #expect(try await impersonated.universeDomain() == (universeDomain ?? "googleapis.com"))
  }

  @Test(
    arguments: [
      (
        "https://other.example.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com.other.example/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://other-iamcredentials.unsupported.example.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com:8443/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/./serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/%2e/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/../serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/%2e%2e/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/%5c/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:signJwt",
        nil as String?
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects//serviceAccounts/:generateAccessToken",
        nil as String?
      ),
      (
        "https://iamcredentials.bad_domain/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "bad_domain"
      ),
      (
        "https://iamcredentials.localhost/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "localhost"
      ),
      (
        "https://iamcredentials.169.254.169.254/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "169.254.169.254"
      ),
      (
        "https://iamcredentials.127.0.0.1/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "127.0.0.1"
      ),
      (
        "https://iamcredentials.example.123/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "example.123"
      ),
      (
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "invalid..domain"
      ),
    ]
  )
  func rejectsInvalidImpersonatedServiceAccountURLsInADC(
    impersonationURL: String,
    universeDomain: String?
  ) throws {
    let universeEntry = universeDomain.map { "\"universe_domain\": \"\($0)\"," } ?? ""
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "\(impersonationURL)",
        \(universeEntry)
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(TestKeys.escapedPKCS8PEM)",
          "client_email": "source@gserviceaccount.com"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
  }

  @Test func rejectsImpersonatedServiceAccountWithInvalidSourceTokenURIInADC() throws {
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "source_credentials": {
          "type": "authorized_user",
          "client_id": "test-client-id",
          "client_secret": "test-client-secret",
          "refresh_token": "test-refresh-token",
          "token_uri": "https://other.example.com/token"
        }
      }
      """
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json")
    try Data(json.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try ADC.resolve(environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path])
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
  }
}
