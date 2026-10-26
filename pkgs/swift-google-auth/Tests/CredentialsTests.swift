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

@Suite(.serialized) struct CredentialsTest {
  @Test func resolveProviderForAnonymous() async throws {
    let credentials = try Credentials(configuration: .anonymous)

    // Verify the backing provider is the new experimental Swift wrapper shell
    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("AnonymousCredentials")
    )

    let headers = try await credentials.headers()
    #expect(headers.isEmpty)
  }

  @Test func resolveProviderForADC() async throws {
    let credentials = try Credentials(configuration: .adc(), environment: [:])

    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("MDSCredentials")
    )
  }

  @Test func resolveProviderForADCMissingFileThrowsCannotLoadFile() throws {
    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .adc(),
        environment: ["GOOGLE_APPLICATION_CREDENTIALS": "/nonexistent/path/to/creds.json"]
      )
    }
    guard case let .cannotLoadFile(message, _) = error else {
      Issue.record("Expected CredentialsError.cannotLoadFile, got \(String(describing: error))")
      return
    }
    #expect(message.contains("/nonexistent/path/to/creds.json"))
  }

  @Test func resolveProviderForADCInvalidJSONThrowsParseError() throws {
    let tempFile = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".json")
    try Data("not-valid-json".utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .adc(),
        environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
      )
    }
    guard case .parseError = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
  }

  @Test func resolveProviderForADCUnknownTypeThrowsNotSupported() throws {
    let tempFile = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".json")
    try Data(#"{"type": "gdch_service_account"}"#.utf8).write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .adc(),
        environment: ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
      )
    }
    guard case let .notSupported(message) = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
    #expect(message.contains("gdch_service_account"))
  }

  @Test func adcNotFoundError() async throws {
    let fileManager = FileManager.default
    let tempDirectoryURL = fileManager.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
      at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    defer {
      try? fileManager.removeItem(at: tempDirectoryURL)
    }
    // Run with an environment that will fail.
    let credentials = try Credentials(
      configuration: .adc(),
      environment: [
        "GCE_METADATA_HOST": "https://not-valid.internal.:1",
        "HOME": tempDirectoryURL.absoluteString,
      ]
    )

    let error = await #expect(throws: CredentialsError.self) {
      try await credentials.headers()
    }
    guard case .cannotFetchToken = error else {
      Issue.record("unexpected error type \(error)")
      return
    }
  }

  @Test func resolveProviderForServiceAccount() async throws {
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
    let mockJSON = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(escapedPEM)",
        "client_email": "test@gserviceaccount.com"
      }
      """
    let credentials = try Credentials(
      configuration: .serviceAccount(keyJSON: Data(mockJSON.utf8))
    )

    #expect(credentials.credentialsProvider is ServiceAccountCredentials)
  }

  @Test func resolveProviderForServiceAccountInvalidPEMThrows() throws {
    let mockJSON = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "-----BEGIN PRIVATE KEY-----\\n-----END PRIVATE KEY-----",
        "client_email": "test@gserviceaccount.com"
      }
      """
    #expect {
      _ = try Credentials(
        configuration: .serviceAccount(keyJSON: Data(mockJSON.utf8))
      )
    } throws: { error in
      guard case CredentialsError.parseError = error else { return false }
      return true
    }
  }

  @Test func resolveProviderForUserCredentials() async throws {
    let mockJSON = """
      {
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "type": "authorized_user"
      }
      """
    let dataData = Data(mockJSON.utf8)

    let credentials = try Credentials(configuration: .user(keyJSON: dataData))

    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("UserCredentials")
    )
  }

  @Test func resolveProviderForExternalAccount() async throws {
    struct MockSubjectTokenProvider: SubjectTokenProvider {
      func subjectToken() async throws -> String { "token" }
    }

    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: MockSubjectTokenProvider()),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    ).with {
      $0.universeDomain = "my-universe.com"
    }

    let credentials = try Credentials(
      configuration: .externalAccount(config)
    )

    #expect(credentials.credentialsProvider is ExternalAccountCredentials)
  }

  @Test func resolveProviderForApiKey() async throws {
    let credentials = try Credentials(configuration: .apiKey("test-api-key"))

    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("ApiKeyCredentials")
    )

    let headers = try await credentials.headers()
    #expect(headers == [("x-goog-api-key", "test-api-key")])
  }

  @Test @MainActor func credentialsCalledFromMainActor() async throws {
    let credentials = try Credentials(configuration: .apiKey("test-key"))
    let headers = try await credentials.headers()
    #expect(headers == [("x-goog-api-key", "test-key")])
  }

  @Test func resolveProviderForImpersonatedServiceAccount() throws {
    let source = try Credentials(configuration: .apiKey("source-key"))
    let config = ImpersonatedServiceAccountConfig(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com"
    )
    let credentials = try Credentials(configuration: .impersonatedServiceAccount(config))
    #expect(credentials.credentialsProvider is ImpersonatedCredentials)
  }
}
