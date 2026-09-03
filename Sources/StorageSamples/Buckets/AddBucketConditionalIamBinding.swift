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

// [START storage_add_bucket_conditional_iam_binding]
import GoogleCloudStorage
import GoogleIAMV1
import GoogleType

public func addBucketConditionalIamBinding(
  client: StorageControlClient, bucketId: String, serviceAccount: String
) async throws {
  let role = "roles/storage.objectViewer"
  let title = "A service account can read prefix-a-*"

  var policy = try await client.getIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.options = .init().with { options in
        options.requestedPolicyVersion = 3
      }
    },
    options: .init()
  )
  let condition = GoogleType.Expr().with {
    $0.expression = "resource.name.startsWith(\"projects/_/buckets/\(bucketId)/objects/prefix-a-\")"
    $0.title = title
    $0.description = "Allows \(serviceAccount) read access to objects starting with `prefix-a-`"
  }
  let binding = GoogleIAMV1.Binding().with {
    $0.role = role
    $0.members = ["serviceAccount:\(serviceAccount)"]
    $0.condition = condition
  }
  policy.version = 3
  policy.bindings.append(binding)
  let updated = try await client.setIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.policy = policy
    },
    options: .init()
  )
  print("Added conditional IAM binding to bucket \(bucketId): \(updated)")
}
// [END storage_add_bucket_conditional_iam_binding]
