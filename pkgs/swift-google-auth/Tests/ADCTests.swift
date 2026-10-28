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
    let validPKCS8PEM = """
      -----BEGIN PRIVATE KEY-----
      MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCcPLcw48+yRt5f
      CXKKIHnvNZHuiriD1nrP17OQpHDTkWTq5+ynEDusFXkauFCbUJHrSOTokXDFHZlu
      3HRWM2tRxg8IZODpExgKtqYhS5peJ5iY8Q6Ur1+WvhBln4M5VMtjW2YiN+zrkiCY
      p04KygGo1UZ92ocBpiSOSkqqXoQj+AqBHRGLK3GPmCLqxgzMk2VGGmpTU1mTLN6O
      2CtFkqPmcadypG0vlEbkUYunQud/MhyDb6ArhwrJQa6X6iOvbar7yxaOy0xix/Xk
      s/hcMyVySrjv2/K/LbaVuEOhhseL/gcI0bP8qvn0dZ8c5l9KcdX/fr6aFcrTcqlu
      u4wdNMv5AgMBAAECggEAMTB2dqiK2DSyx1Yony9ZZIRHtUQskqmA0hY13SjAswOY
      M9MgMXsNZoD+N3jnO/cScfLpywUbbZwDliFHaWpX9A945Sopm4gc7iaSSHJOoC00
      QJbIgexzGnktnWkqve6h+F6q2cQkzggcRiOKkSAHhLndLzuRfOXrpXbjah9G2DG9
      5CIWjY/VdZQrwWrmzkY2WJVoW52Cfj5TBmCbpNk0Rdbv5q1957TGscQKELxp3wt9
      ash4KGg2NlAP/fjRLs+X+9/dSxV8RHnovxPnXVy5XDcGisSX8rHjsjV3rZTs2Nls
      ug1kJcAgg9i51wgsvE8Fu3lzLC3ewYmpilI5O8XA9wKBgQDafd7Hu7LMP9UisX4y
      FTuxLZUoeN7erutAWzO8deyTFM/BW1blzQBHCAUA1cMPftdFaFPfgBaz6CkikhMv
      0ySPjyyKsVDVObKCKo0XxISrdiuqE1K62Yn/gfyh8ZdEv+qkJvz1XaBb8DrlbpqK
      EAXeLsckPV6lUqcv7BhojdeTmwKBgQC3Duy9rw8yxWpvfRubsuT7CQ7p6YTM1KAx
      egNiKBGx6sj3KWGVcJPCPZkaD1+XJO6zhOqyL5/syviFTDuyEIWYBaY0odJwb7Vg
      KVXdBa5UwI6DYmsZAAAOP1wywwQrYuqwuVhy3+09iKPkGOJ4I32Kw5HYvJ79qL19
      sRE0/e3p+wKBgFG/8MAYuaB0bcHKWWZRzYDQhlObTgBRwFHXDfeAw+CQU9+L1mqr
      FmR9WqniUVaV5ePhUih424W64tE9iJJHVRGlx0upZo4xRVowo5P2ApHI6DN9gWHK
      DTkdoLHTG/8sM5XxxInl2x8rNk4r4QSxVBC6veYQVD5VO5rRopxUHgnrAoGAeHZq
      1hw4PSnqc7l5jIk54/S/CrDwAja9wDFRvqstkc42N2fU3pl5sq4EbUDGn9je9+W0
      6FMsw4+B4X4cHn5+216EVEhVCkaIreIlrc/KO92HKvB+F7KHVtjdHE53FPIADRG7
      IcU4AnFDoJu7lGGOgN1Xwa/GVJhRMkBuWVfs0zcCgYEAlP9KCxjRXtcJEnB81uHx
      sjUYPwyP5KbyYnl9LRbqfvZPIMgV2BIl+wOLUhSFYpxsDK3Otf/SyKm3qkifT4E2
      TEsACTOH4L3aH53EIDbugMPAyMbsTZfR4EK2zGi1QOl0hjZ+kUSNcPlDAUK9vXfF
      1ARUsyX+ffQ++dMyCItdcEg=
      -----END PRIVATE KEY-----
      """
    let escapedPEM = validPKCS8PEM.replacingOccurrences(of: "\n", with: "\\n")
    let json = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(escapedPEM)",
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

  @Test func resolvesImpersonatedServiceAccountWithAuthorizedUserSourceFromFile() throws {
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
    #expect(impersonated.universeDomain == "googleapis.com")
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
    let validPKCS8PEM = """
      -----BEGIN PRIVATE KEY-----
      MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCcPLcw48+yRt5f
      CXKKIHnvNZHuiriD1nrP17OQpHDTkWTq5+ynEDusFXkauFCbUJHrSOTokXDFHZlu
      3HRWM2tRxg8IZODpExgKtqYhS5peJ5iY8Q6Ur1+WvhBln4M5VMtjW2YiN+zrkiCY
      p04KygGo1UZ92ocBpiSOSkqqXoQj+AqBHRGLK3GPmCLqxgzMk2VGGmpTU1mTLN6O
      2CtFkqPmcadypG0vlEbkUYunQud/MhyDb6ArhwrJQa6X6iOvbar7yxaOy0xix/Xk
      s/hcMyVySrjv2/K/LbaVuEOhhseL/gcI0bP8qvn0dZ8c5l9KcdX/fr6aFcrTcqlu
      u4wdNMv5AgMBAAECggEAMTB2dqiK2DSyx1Yony9ZZIRHtUQskqmA0hY13SjAswOY
      M9MgMXsNZoD+N3jnO/cScfLpywUbbZwDliFHaWpX9A945Sopm4gc7iaSSHJOoC00
      QJbIgexzGnktnWkqve6h+F6q2cQkzggcRiOKkSAHhLndLzuRfOXrpXbjah9G2DG9
      5CIWjY/VdZQrwWrmzkY2WJVoW52Cfj5TBmCbpNk0Rdbv5q1957TGscQKELxp3wt9
      ash4KGg2NlAP/fjRLs+X+9/dSxV8RHnovxPnXVy5XDcGisSX8rHjsjV3rZTs2Nls
      ug1kJcAgg9i51wgsvE8Fu3lzLC3ewYmpilI5O8XA9wKBgQDafd7Hu7LMP9UisX4y
      FTuxLZUoeN7erutAWzO8deyTFM/BW1blzQBHCAUA1cMPftdFaFPfgBaz6CkikhMv
      0ySPjyyKsVDVObKCKo0XxISrdiuqE1K62Yn/gfyh8ZdEv+qkJvz1XaBb8DrlbpqK
      EAXeLsckPV6lUqcv7BhojdeTmwKBgQC3Duy9rw8yxWpvfRubsuT7CQ7p6YTM1KAx
      egNiKBGx6sj3KWGVcJPCPZkaD1+XJO6zhOqyL5/syviFTDuyEIWYBaY0odJwb7Vg
      KVXdBa5UwI6DYmsZAAAOP1wywwQrYuqwuVhy3+09iKPkGOJ4I32Kw5HYvJ79qL19
      sRE0/e3p+wKBgFG/8MAYuaB0bcHKWWZRzYDQhlObTgBRwFHXDfeAw+CQU9+L1mqr
      FmR9WqniUVaV5ePhUih424W64tE9iJJHVRGlx0upZo4xRVowo5P2ApHI6DN9gWHK
      DTkdoLHTG/8sM5XxxInl2x8rNk4r4QSxVBC6veYQVD5VO5rRopxUHgnrAoGAeHZq
      1hw4PSnqc7l5jIk54/S/CrDwAja9wDFRvqstkc42N2fU3pl5sq4EbUDGn9je9+W0
      6FMsw4+B4X4cHn5+216EVEhVCkaIreIlrc/KO92HKvB+F7KHVtjdHE53FPIADRG7
      IcU4AnFDoJu7lGGOgN1Xwa/GVJhRMkBuWVfs0zcCgYEAlP9KCxjRXtcJEnB81uHx
      sjUYPwyP5KbyYnl9LRbqfvZPIMgV2BIl+wOLUhSFYpxsDK3Otf/SyKm3qkifT4E2
      TEsACTOH4L3aH53EIDbugMPAyMbsTZfR4EK2zGi1QOl0hjZ+kUSNcPlDAUK9vXfF
      1ARUsyX+ffQ++dMyCItdcEg=
      -----END PRIVATE KEY-----
      """
    let escapedPEM = validPKCS8PEM.replacingOccurrences(of: "\n", with: "\\n")
    let json = """
      {
        "type": "impersonated_service_account",
        "service_account_impersonation_url": "https://iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        "universe_domain": "my-universe.com",
        "source_credentials": {
          "type": "service_account",
          "project_id": "test-project-id",
          "private_key_id": "test-private-key-id",
          "private_key": "\(escapedPEM)",
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
    #expect(impersonated.universeDomain == "my-universe.com")
    #expect(impersonated.provider.sourceCredentials is ServiceAccountCredentials)
    let sourceHeaders = try await impersonated.provider.sourceCredentials.headers()
    #expect(sourceHeaders["Authorization"]?.hasPrefix("Bearer ") == true)
  }

  @Test func normalizesEmptyUniverseDomainAndQuotaProjectInImpersonatedADC() throws {
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
    #expect(impersonated.universeDomain == "googleapis.com")
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
}
