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

@testable import GoogleCloudAuth

@Suite(.serialized) struct CredentialsTest {
  @Test func resolveProviderForAnonymous() async throws {
    let credentials = try Credentials(configuration: .anonymous)

    // Verify the backing provider is the new experimental Swift wrapper shell
    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("AnonymousCredentials")
    )

    let headers = try await credentials.headers()
    #expect(headers.isEmpty)

    let ud = await credentials.universeDomain()
    #expect(ud == nil)
  }

  @Test func resolveProviderForADC() async throws {
    let credentials = try Credentials(configuration: .adc(environment: [:]))

    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("MDSCredentials")
    )
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
      configuration: try .adc(environment: [
        "GCE_METADATA_HOST": "https://not-valid.internal.:1",
        "HOME": tempDirectoryURL.absoluteString,
        "__TEST_SIMULATE_ADC": "true",
      ]))

    let error = await #expect(throws: CredentialsError.self) {
      try await credentials.headers()
    }
    guard case .cannotFetchToken = error else {
      Issue.record("unexpected error type \(error)")
      return
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

    let ud = await credentials.universeDomain()
    #expect(ud == nil)
  }

  @Test func resolveProviderForProgrammaticExternalAccount() async throws {
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
      configuration: .programmaticExternalAccount(config)
    )

    #expect(credentials.credentialsProvider is ExternalAccountCredentials)

    let ud = await credentials.universeDomain()
    #expect(ud == "my-universe.com")
  }

  @Test func resolveProviderForApiKey() async throws {
    let credentials = try Credentials(configuration: .apiKey("test-api-key"))

    #expect(
      String(describing: type(of: credentials.credentialsProvider)).contains("ApiKeyCredentials")
    )

    let headers = try await credentials.headers()
    #expect(headers.count == 1)
    #expect(
      headers.contains { $0.0 == "x-goog-api-key" && $0.1 == "test-api-key" },
      "Missing x-goog-api-key header in \(headers)"
    )

    let ud = await credentials.universeDomain()
    #expect(ud == nil)
  }
}
