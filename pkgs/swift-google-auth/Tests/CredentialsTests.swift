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
    let mockJSON = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
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

  @Test func resolveProviderForImpersonatedServiceAccount() async throws {
    let source = try Credentials(configuration: .apiKey("source-key"))
    let config = ImpersonatedServiceAccountConfig(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com"
    )
    let credentials = try Credentials(configuration: .impersonatedServiceAccount(config))
    #expect(credentials.credentialsProvider is ImpersonatedCredentials)
    #expect(try await credentials.universeDomain() == Credentials.defaultUniverseDomain)
    #expect(!credentials._isAnonymous)
  }

  @Test func defaultUniverseDomainAndAnonymousFlags() async throws {
    #expect(Credentials.defaultUniverseDomain == "googleapis.com")

    let anon = try Credentials(configuration: .anonymous)
    #expect(anon._isAnonymous)
    #expect(try await anon.universeDomain() == "googleapis.com")

    let apiKey = try Credentials(configuration: .apiKey("test-api-key"))
    #expect(!apiKey._isAnonymous)
    #expect(try await apiKey.universeDomain() == "googleapis.com")
  }
}
