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

@Suite("ADC Resolver Tests")
struct ADCResolverTests {
  @Test("load ADC no file at env is error")
  func loadADCNoFileAtEnvIsError() {
    let env = ["GOOGLE_APPLICATION_CREDENTIALS": "file-does-not-exist.json"]
    #expect(throws: ADCResolverError.self) {
      _ = try loadADC(environment: env)
    }
  }

  @Test("load ADC no well known path fallback to mds")
  func loadADCNoWellKnownPathFallbackToMDS() throws {
    let env: [String: String] = [:]
    let result = try loadADC(environment: env)
    #expect(result == .fallbackToMds)
  }

  @Test("load ADC success")
  func loadADCSuccess() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
    let contents = Data("contents".utf8)
    try contents.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let env = ["GOOGLE_APPLICATION_CREDENTIALS": tempFile.path]
    let result = try loadADC(environment: env)
    #expect(result == .contents(contents))
  }

  @Test("create access token credentials fallback to mds with quota project override")
  func createAccessTokenCredentialsFallbackToMDSWithQuotaProjectOverride() throws {
    let env = ["GOOGLE_CLOUD_QUOTA_PROJECT": "env-quota-project"]
    let creds = try ADC.resolve(quotaProjectID: "test-quota-project", environment: env)

    // Validate it fell back to MDS with the correct quota project ID from the environment overriding the config
    let mdsCreds = try #require(creds as? MDSCredentials)
    #expect(mdsCreds.quotaProjectID == "env-quota-project")
  }
}
