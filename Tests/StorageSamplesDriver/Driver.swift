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
import StorageSamples
import GoogleCloudGax
import GoogleCloudStorage
import Testing

@Suite struct StorageSamplesDriver {
  @Test(.enabled(if: Self.enabled())) func runBucketSamples() async throws {
    let projectId = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    let client = try Self.makeClient()
    var bucketNames: [String] = []
    do {
      try await StorageSamples.runBucketSamples(
        client: client, projectId: projectId, bucketNames: &bucketNames)
      await StorageSamples.cleanupTestBuckets(client: client, bucketNames: bucketNames)
    } catch {
      await StorageSamples.cleanupTestBuckets(client: client, bucketNames: bucketNames)
      throw error
    }
  }

  @Test(.enabled(if: Self.enabled())) func stale() async throws {
    let projectId = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]!
    let client = try Self.makeClient()
    await StorageSamples.cleanupStaleTestBuckets(client: client, projectId: projectId)
  }

  static func makeClient() throws -> StorageControlClient {
    try StorageControlClient(
      .init().with {
        $0.backoffPolicy = ExponentialBackoff(
          clamping: .init().with { $0.initialDelay = .seconds(2) })
      })
  }

  static func enabled() -> Bool {
    ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
  }
}
