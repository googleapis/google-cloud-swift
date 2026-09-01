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

// [START storage_create_bucket_with_encryption_enforcement]
import GoogleCloudStorage

public func createBucketWithEncryptionEnforcement(
  client: StorageControlClient, projectId: String, bucketId: String
) async throws {
  // Note that this example uses Google-managed encryption keys (GMEK) with FullyRestricted.
  // More options are available, please consult the documentation.
  let bucket =
    try await client
    .createBucket(
      request: .init().with {
        $0.parent = "projects/_"
        $0.bucketId = bucketId
        $0.bucket = .init().with { bucket in
          bucket.project = "projects/\(projectId)"
          bucket.encryption = .init().with { e in
            e.googleManagedEncryptionEnforcementConfig = .init().with { ec in
              ec.restrictionMode = "FullyRestricted"
            }
          }
        }
      }, options: .init())
  print("successfully created bucket \(bucket)")
}
// [END storage_create_bucket_with_encryption_enforcement]
