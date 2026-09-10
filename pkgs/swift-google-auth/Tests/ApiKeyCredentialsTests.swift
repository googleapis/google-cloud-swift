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

@Suite struct ApiKeyCredentialsTests {
  @Test func debugDescriptionRedactsApiKey() {
    let credentials = ApiKeyCredentials(apiKey: "super-secret-api-key")
    let description = String(reflecting: credentials)

    #expect(!description.contains("super-secret-api-key"))
    #expect(description.contains("[redacted]"))
  }

  @Test func headersProducesExpectedApiKeyHeader() async throws {
    let credentials = ApiKeyCredentials(apiKey: "test-api-key")
    let headers = try await credentials.headers()

    #expect(headers.count == 1)
    #expect(
      headers.contains { $0.0 == "x-goog-api-key" && $0.1 == "test-api-key" },
      "Missing x-goog-api-key header in \(headers)"
    )
  }

  @Test func universeDomainReturnsNil() async {
    let credentials = ApiKeyCredentials(apiKey: "test-api-key")
    let universeDomain = await credentials.universeDomain()

    #expect(universeDomain == nil)
  }
}
