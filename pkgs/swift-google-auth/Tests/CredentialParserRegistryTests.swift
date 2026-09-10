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

import Dispatch
import Testing

@testable import GoogleCloudAuth

struct MockCredentialsProvider: CredentialsProvider {
  func headers() async throws -> [(String, String)] {
    return [("Authorization", "Bearer mock")]
  }
  func universeDomain() async -> String? {
    return nil
  }
}

struct MockParser: CredentialSourceParser {
  static let type = "mock_type"
  init() {}
  func parse(
    config: [String: Any],
    quotaProjectID: String?,
    universeDomain: String?,
    scopes: [String],
    environment: [String: String]
  ) throws -> any CredentialsProvider {
    return MockCredentialsProvider()
  }
}

@Suite("Credential Parser Registry Tests")
struct CredentialParserRegistryTests {
  @Test("Registry allows dynamic registration and parsing")
  func dynamicRegistration() throws {
    let registry = CredentialParserRegistry.shared

    // Unregistered type should return nil
    let nilResult = try registry.parse(
      type: "unregistered_mock",
      config: [:],
      quotaProjectID: nil,
      universeDomain: nil,
      scopes: [],
      environment: [:]
    )
    #expect(nilResult == nil)

    // Register the parser
    registry.register(parser: MockParser.self)

    // Registered type should return valid source
    let source = try registry.parse(
      type: "mock_type",
      config: [:],
      quotaProjectID: nil,
      universeDomain: nil,
      scopes: [],
      environment: [:]
    )
    #expect(source != nil)
    #expect(source is MockCredentialsProvider)
  }

  @Test("Registry has no obvious thread-safety problems for concurrent registrations")
  func threadSafety() async throws {
    let registry = CredentialParserRegistry.shared

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask {
          registry.register(parser: MockParser.self)
        }
      }
    }

    let source = try registry.parse(
      type: "mock_type",
      config: [:],
      quotaProjectID: nil,
      universeDomain: nil,
      scopes: [],
      environment: [:]
    )
    #expect(source != nil)
  }
}
