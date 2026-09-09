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

// [START storage_control_update_anywhere_cache]
import GoogleCloudStorage
import GoogleCloudWKT

public func updateAnywhereCache(
  client: StorageControlClient, bucketId: String, cacheId: String
) async throws {
  // TODO(https://github.com/googleapis/google-cloud-swift/issues/588) - use the LRO helper
  var operation = try await client.updateAnywhereCache(
    request: .init().with {
      $0.anywhereCache = .init().with { cache in
        cache.name = "projects/_/buckets/\(bucketId)/anywhereCaches/\(cacheId)"
        cache.admissionPolicy = "admit-on-second-miss"
      }
      $0.updateMask = .init(paths: ["admission_policy"])
    }
  )
  while !operation.done {
    try await Task.sleep(for: .seconds(1))
    operation = try await client.getOperation(
      request: .init().with {
        $0.name = operation.name
      }
    )
  }
  print("Updated anywhere cache: \(operation)")
}
// [END storage_control_update_anywhere_cache]
