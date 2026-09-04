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

// [START storage_change_default_storage_class]
import GoogleCloudStorage

public func changeDefaultStorageClass(
  client: StorageControlClient, bucketId: String, storageClass: String
) async throws {
  let bucket = try await client.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  let _ = try await client.updateBucket(
    request: .init().with {
      $0.bucket = bucket.with { bucket in
        bucket.storageClass = storageClass
      }
      $0.ifMetagenerationMatch = bucket.metageneration
      $0.updateMask = .init(paths: ["storage_class"])
    },
    options: .init()
  )
  print("Default storage class for bucket \(bucketId) set to \(storageClass)")
}
// [END storage_change_default_storage_class]
