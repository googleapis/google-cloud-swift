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

// [START storage_quota_project]
import GoogleCloudGax
import GoogleCloudStorage

public func quotaProject(bucketId: String, projectId: String) async throws {
  let control = try StorageControlClient()

  // Request using a specific quota project for control plane operations
  let bucket = try await control.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: RequestOptions().with {
      $0.quotaProject = projectId
    }
  )
  print("Bucket \(bucketId) metadata is \(bucket)")

  let client = try StorageClient()

  let objectName = "hello-world.txt"

  // Request using a specific quota project for data plane operations
  let reader = client.readObject(
    from: "projects/_/buckets/\(bucketId)",
    object: objectName,
    options: ReadObjectOptions().with {
      $0.quotaProject = projectId
    }
  )
  let metadata = try await reader.metadata
  print("Object highlights: \(metadata)")
}
// [END storage_quota_project]
