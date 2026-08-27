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

@Suite struct ADCTest {
  @Test func resolvesToMDSCredentials() async throws {
    let provider = try ADC.resolve(environment: [:])
    #expect(provider is MDSCredentials)

    let ud = await provider.universeDomain()
    #expect(ud == nil)
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
}
