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
import JWTKit
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

    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.provider.fromADC == true)
    #expect(mds.quotaProjectID == nil)
    #expect(mds.provider.scopes.isEmpty)
  }

  @Test func resolveProviderForADCCustomOptions() async throws {
    let config = ADCConfig().with {
      $0.quotaProjectID = "my-adc-quota-project"
      $0.universeDomain = "custom.universe.com"
      $0.scopes = ["scope-a", "scope-b"]
    }
    let credentials = try Credentials(configuration: .adc(config), environment: [:])

    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.provider.fromADC == true)
    #expect(mds.quotaProjectID == "my-adc-quota-project")
    #expect(mds.provider.scopes == ["scope-a", "scope-b"])
    #expect(try await credentials.universeDomain() == "custom.universe.com")
    try await credentials.validateUniverseDomain("custom.universe.com")

    let envPrecedenceCredentials = try Credentials(
      configuration: .adc(config),
      environment: ["GOOGLE_CLOUD_QUOTA_PROJECT": "env-quota-project"]
    )
    let envMDS = try #require(envPrecedenceCredentials.credentialsProvider as? MDSCredentials)
    #expect(envMDS.quotaProjectID == "env-quota-project")
  }

  @Test func resolveProviderForADCWithNoGCECheckThrowsCredentialsNotFound() throws {
    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .adc(),
        environment: ["NO_GCE_CHECK": "true"]
      )
    }
    guard case let .credentialsNotFound(message) = error else {
      Issue.record(
        "Expected CredentialsError.credentialsNotFound, got \(String(describing: error))")
      return
    }
    #expect(message.contains("NO_GCE_CHECK"))
    #expect(message.contains("gcloud auth application-default login"))
  }

  @Test func resolveProviderForADCWithNoGCECheckThrowsEvenWithMetadataHost() throws {
    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .adc(),
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
    let config = ServiceAccountConfig(keyJSON: Data(mockJSON.utf8))
    let credentials = try Credentials(configuration: .serviceAccount(config))

    #expect(credentials.credentialsProvider is ServiceAccountCredentials)
    let headers = try await credentials.headers()
    #expect(headers["Authorization"]?.hasPrefix("Bearer ") == true)
    #expect(headers["x-goog-user-project"] == nil)
    #expect(try await credentials.universeDomain() == "googleapis.com")
  }

  @Test func resolveProviderForServiceAccountCustomOptions() async throws {
    let mockJSON = """
      {
        "type": "service_account",
        "project_id": "test-project-id",
        "private_key_id": "test-private-key-id",
        "private_key": "\(TestKeys.escapedPKCS8PEM)",
        "client_email": "test@gserviceaccount.com"
      }
      """
    let keyData = Data(mockJSON.utf8)
    let audienceConfig = ServiceAccountConfig(keyJSON: keyData).with {
      $0.quotaProjectID = "sa-quota-project"
      $0.universeDomain = "custom.universe.com"
      $0.accessSpecifier = .audience("https://pubsub.googleapis.com/")
    }
    let audienceCredentials = try Credentials(configuration: .serviceAccount(audienceConfig))
    let audienceHeaders = try await audienceCredentials.headers()
    #expect(audienceHeaders["x-goog-user-project"] == "sa-quota-project")
    #expect(try await audienceCredentials.universeDomain() == "custom.universe.com")

    let token = try #require(
      audienceHeaders["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
    )
    let key = try JSONDecoder().decode(ServiceAccountData.self, from: keyData)
    let privateKey = try Insecure.RSA.PrivateKey(pem: key.privateKey)
    let keys = JWTKeyCollection()
    await keys.add(rsa: privateKey, digestAlgorithm: .sha256)
    let decodedAudienceClaims = try await keys.verify(token, as: ServiceAccountClaims.self)
    #expect(decodedAudienceClaims.aud?.value.first == "https://pubsub.googleapis.com/")
    #expect(decodedAudienceClaims.scope == nil)

    let scopesConfig = ServiceAccountConfig(keyJSON: keyData).with {
      $0.accessSpecifier = .scopes(["scope-a", "scope-b"])
    }
    let scopesCredentials = try Credentials(configuration: .serviceAccount(scopesConfig))
    let scopesHeaders = try await scopesCredentials.headers()
    let scopesToken = try #require(
      scopesHeaders["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
    )
    let decodedScopesClaims = try await keys.verify(scopesToken, as: ServiceAccountClaims.self)
    #expect(decodedScopesClaims.scope == "scope-a scope-b")
    #expect(decodedScopesClaims.aud == nil)
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
    let config = ServiceAccountConfig(keyJSON: Data(mockJSON.utf8))
    #expect {
      _ = try Credentials(configuration: .serviceAccount(config))
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
    let keyData = Data(mockJSON.utf8)

    let credentials = try Credentials(configuration: .user(UserConfig(keyJSON: keyData)))

    let userCreds = try #require(
      credentials.credentialsProvider as? UserCredentialsGeneric<ContinuousClock>
    )
    #expect(userCreds.quotaProjectID == nil)
    #expect(userCreds.provider.scopes.isEmpty)
    #expect(try await credentials.universeDomain() == "googleapis.com")
  }

  @Test func resolveProviderForUserCredentialsCustomOptions() async throws {
    let mockJSON = """
      {
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token",
        "type": "authorized_user"
      }
      """
    let keyData = Data(mockJSON.utf8)
    let config = UserConfig(keyJSON: keyData).with {
      $0.quotaProjectID = "user-quota-project"
      $0.universeDomain = "googleapis.com"
      $0.scopes = ["scope-a", "scope-b"]
    }
    let credentials = try Credentials(configuration: .user(config))

    let userCreds = try #require(
      credentials.credentialsProvider as? UserCredentialsGeneric<ContinuousClock>
    )
    #expect(userCreds.quotaProjectID == "user-quota-project")
    #expect(userCreds.provider.scopes == ["scope-a", "scope-b"])
    #expect(try await credentials.universeDomain() == "googleapis.com")

    let customUniverseConfig = UserConfig(keyJSON: keyData).with {
      $0.universeDomain = "custom.universe.com"
    }
    let error = #expect(throws: CredentialsError.self) {
      _ = try Credentials(configuration: .user(customUniverseConfig))
    }
    guard case .notSupported = error else {
      Issue.record("Expected CredentialsError.notSupported, got \(String(describing: error))")
      return
    }
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

  @Test func resolveProviderForAPIKey() async throws {
    let credentials = try Credentials(configuration: .apiKey("test-api-key"))

    #expect(credentials.credentialsProvider is APIKeyCredentials)

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
    try await credentials.validateUniverseDomain(Credentials.defaultUniverseDomain)
  }

  @Test func resolveProviderForMDSDefaults() throws {
    let credentials = try Credentials(
      configuration: .mds(),
      environment: ["GOOGLE_CLOUD_QUOTA_PROJECT": "adc-only-quota-project"]
    )
    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.provider.fromADC == false)
    #expect(mds.quotaProjectID == nil)
    #expect(mds.provider.scopes.isEmpty)
  }

  @Test func resolveProviderForMDSCustomOptions() async throws {
    let config = MDSConfig().with {
      $0.quotaProjectID = "my-quota-project"
      $0.universeDomain = "custom.universe.com"
      $0.scopes = ["scope-a", "scope-b"]
    }
    let credentials = try Credentials(
      configuration: .mds(config),
      environment: [
        "GCE_METADATA_HOST": "127.0.0.1:8080",
        "GOOGLE_CLOUD_QUOTA_PROJECT": "ignored-env-quota",
      ]
    )
    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.provider.fromADC == false)
    #expect(mds.quotaProjectID == "my-quota-project")
    #expect(mds.provider.scopes == ["scope-a", "scope-b"])
    #expect(mds.provider.environment["GCE_METADATA_HOST"] == "127.0.0.1:8080")
    #expect(try await credentials.universeDomain() == "custom.universe.com")
    try await credentials.validateUniverseDomain("custom.universe.com")
  }

  @Test func resolveProviderForMDSIgnoresADCEnvironmentVariables() throws {
    let credentials = try Credentials(
      configuration: .mds(),
      environment: [
        "NO_GCE_CHECK": "true",
        "GOOGLE_APPLICATION_CREDENTIALS": "/nonexistent/path/to/creds.json",
      ]
    )
    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.provider.fromADC == false)
  }

  @Test func resolveProviderForMDSNormalizesEmptyStrings() throws {
    let config = MDSConfig().with {
      $0.quotaProjectID = ""
      $0.universeDomain = ""
    }
    let credentials = try Credentials(
      configuration: .mds(config),
      environment: [:]
    )
    let mds = try #require(credentials.credentialsProvider as? MDSCredentials)
    #expect(mds.quotaProjectID == nil)
  }

  @Test func defaultUniverseDomainAndValidation() async throws {
    #expect(Credentials.defaultUniverseDomain == "googleapis.com")

    let anon = try Credentials(configuration: .anonymous)
    #expect(try await anon.universeDomain() == "googleapis.com")
    try await anon.validateUniverseDomain("googleapis.com")
    try await anon.validateUniverseDomain("custom.universe.com")

    let apiKey = try Credentials(configuration: .apiKey("test-api-key"))
    #expect(try await apiKey.universeDomain() == "googleapis.com")
    try await apiKey.validateUniverseDomain("googleapis.com")
    await #expect(throws: CredentialsError.self) {
      try await apiKey.validateUniverseDomain("custom.universe.com")
    }
  }
}
