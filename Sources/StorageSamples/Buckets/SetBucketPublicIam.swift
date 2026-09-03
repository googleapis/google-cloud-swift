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

// [START storage_set_bucket_public_iam]
import GoogleCloudStorage
import GoogleIAMV1

func setBucketPublicIam(
  client: StorageControlClient,
  bucketId: String
) async throws {
  var policy = try await client.getIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )

  policy.bindings.append(
    .init().with {
      $0.role = "roles/storage.objectViewer"
      $0.members = ["allUsers"]
    }
  )

  let updatedPolicy = try await client.setIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.policy = policy
    },
    options: .init()
  )

  print("Successfully set public IAM policy for bucket \(bucketId)")
  print("The updated policy is: \(updatedPolicy)")
}
// [END storage_set_bucket_public_iam]
