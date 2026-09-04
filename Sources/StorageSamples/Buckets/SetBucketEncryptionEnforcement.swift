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

// [START storage_set_bucket_encryption_enforcement]
import GoogleCloudStorage

public func setBucketEncryptionEnforcement(
  client: StorageControlClient, bucketId: String
) async throws {
  let bucket = try await client.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  let updated = try await client.updateBucket(
    request: .init().with {
      $0.bucket = bucket.with { bucket in
        bucket.encryption = .init().with { encryption in
          encryption.googleManagedEncryptionEnforcementConfig = .init().with { config in
            config.restrictionMode = "FullyRestricted"
          }
        }
      }
      $0.ifMetagenerationMatch = bucket.metageneration
      $0.updateMask = .init(paths: ["encryption.google_managed_encryption_enforcement_config"])
    },
    options: .init()
  )
  print(
    "Updated encryption enforcement on bucket \(bucketId): \(String(describing: updated.encryption))"
  )
}
// [END storage_set_bucket_encryption_enforcement]
