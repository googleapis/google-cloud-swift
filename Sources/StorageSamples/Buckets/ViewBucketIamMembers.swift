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

// [START storage_view_bucket_iam_members]
import GoogleCloudStorage
import GoogleIAMV1

public func viewBucketIamMembers(
  client: StorageControlClient, bucketId: String
) async throws {
  let policy = try await client.getIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.options = .init().with { options in
        options.requestedPolicyVersion = 3
      }
    },
    options: .init()
  )
  for binding in policy.bindings {
    print("Role: \(binding.role), Members: \(binding.members)")
    if let condition = binding.condition {
      print("Condition: \(condition.expression)")
    }
  }
}
// [END storage_view_bucket_iam_members]
