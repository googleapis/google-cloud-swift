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
@testable import StorageW1R3
import Testing

@Suite(.enabled(if: storageW1R3IntegrationEnabled()))
struct StorageW1R3IntegrationTests {
  @Test func smoke() async throws {
    let bucketName = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!
    let benchmark = StorageW1R3().with {
      $0.bucketName = bucketName
      $0.minObjectSize = 0
      $0.maxObjectSize = 16 * 1024
      $0.taskCount = 1
      $0.iterations = 4
    }
    let counters = try await benchmark.runBenchmark()
    #expect(await counters.sampleCount > 0)
    #expect(await counters.writeError == 0)
    #expect(await counters.readError == 0)
    #expect(await counters.deleteError == 0)
  }
}

func storageW1R3IntegrationEnabled() -> Bool {
  ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
    && ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] != nil
}
