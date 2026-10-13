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

import ArgumentParser
@testable import Endurance
import Testing

@Suite struct ValidationTests {
  @Test func defaultsAreValid() throws {
    let parsed = try Endurance.parseAsRoot([])
    guard let endurance = parsed as? Endurance else {
      Issue.record("cannot convert to Endurance")
      return
    }
    try endurance.validate()
    #expect(endurance.requestsPerMinute == 80_000)
    #expect(endurance.iterations == nil)
  }

  @Test func validConfigurationPasses() throws {
    let parsed = try Endurance.parseAsRoot([
      "--requests-per-minute=10_000",
      "--iterations=5",
    ])
    guard let endurance = parsed as? Endurance else {
      Issue.record("cannot convert to Endurance")
      return
    }
    try endurance.validate()
    #expect(endurance.requestsPerMinute == 10_000)
    #expect(endurance.iterations == 5)
  }

  @Test func requestRateAliasPasses() throws {
    let parsed = try Endurance.parseAsRoot(["--request-rate=5000"])
    guard let endurance = parsed as? Endurance else {
      Issue.record("cannot convert to Endurance")
      return
    }
    try endurance.validate()
    #expect(endurance.requestsPerMinute == 5_000)
  }

  @Test(arguments: [
    ["--requests-per-minute=0"],
    ["--requests-per-minute=-100"],
    ["--requests-per-minute=not-a-number"],
    ["--iterations=0"],
    ["--iterations=-1"],
  ])
  func invalidConfigurationThrows(args: [String]) throws {
    #expect(throws: (any Error).self) {
      let _ = try Endurance.parseAsRoot(args)
    }
  }

  @Test func enduranceErrorDescriptions() {
    #expect(
      EnduranceError.missingProjectId.description
        == "GOOGLE_CLOUD_PROJECT environment variable is not set"
    )
    #expect(
      EnduranceError.noEnduranceSecretsFound(projectId: "my-project").description
        == "no secrets with the `endurance-test` label found in my-project"
    )
  }
}
