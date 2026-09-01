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

// [START storage_create_bucket_with_object_retention]
import GoogleCloudStorage

public func createBucketWithObjectRetention(
  client: StorageControlClient, projectId: String, bucketId: String
) async throws {
  let bucket =
    try await client
    .createBucket(
      request: .init().with {
        $0.parent = "projects/_"
        $0.bucketId = bucketId
        $0.bucket = .init().with { bucket in
          bucket.project = "projects/\(projectId)"
          bucket.objectRetention = .init().with { or in
            or.enabled = true
          }
        }
      }, options: .init())
  print("successfully created bucket \(bucket)")
}
// [END storage_create_bucket_with_object_retention]
