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

// [START storage_add_bucket_owner]
import GoogleCloudStorage

public func addBucketOwner(
  client: StorageControlClient, bucketId: String, userEmail: String
) async throws {
  let bucket = try await client.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  var acl = bucket.acl
  let entity = "user-\(userEmail)"
  if let index = acl.firstIndex(where: { $0.entity == entity }) {
    acl[index].role = "OWNER"
  } else {
    acl.append(
      BucketAccessControl().with {
        $0.entity = entity
        $0.role = "OWNER"
      }
    )
  }
  let updated = try await client.updateBucket(
    request: .init().with {
      $0.bucket = bucket.with { bucket in
        bucket.acl = acl
      }
      $0.ifMetagenerationMatch = bucket.metageneration
      $0.updateMask = .init(paths: ["acl"])
    },
    options: .init()
  )
  print("Added \(userEmail) as an owner on \(bucketId): \(updated)")
}
// [END storage_add_bucket_owner]
