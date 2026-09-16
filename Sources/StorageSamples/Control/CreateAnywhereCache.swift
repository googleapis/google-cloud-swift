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

// [START storage_control_create_anywhere_cache]
import GoogleCloudStorage

public func createAnywhereCache(
  client: StorageControlClient, bucketId: String, zone: String
) async throws {
  let poller = try await client.createAnywhereCache(
    withPolling: .init().with {
      $0.parent = "projects/_/buckets/\(bucketId)"
      $0.anywhereCache = .init().with { cache in
        cache.zone = zone
        cache.name = "projects/_/buckets/\(bucketId)/anywhereCaches/\(zone)"
      }
    }
  )
  let cache = try await poller.wait()
  print("Created anywhere cache: \(cache)")
}
// [END storage_control_create_anywhere_cache]
