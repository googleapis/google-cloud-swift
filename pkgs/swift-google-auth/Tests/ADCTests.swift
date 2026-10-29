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
    #expect(provider is GoogleAuth.UserCredentials)
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
    #expect(impersonated.provider.sourceCredentials is GoogleAuth.UserCredentials)
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
          "client_email": "source@gserviceaccount.com"
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
          "refresh_token": "test-refresh-token"
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
    #expect(inner.provider.sourceCredentials is GoogleAuth.UserCredentials)
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
}
