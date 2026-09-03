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

// [START storage_remove_bucket_iam_member]
import GoogleCloudStorage
import GoogleIAMV1

public func removeBucketIamMember(
  client: StorageControlClient, bucketId: String, role: String, member: String
) async throws {
  var policy = try await client.getIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.options = .init().with { options in
        options.requestedPolicyVersion = 3
      }
    },
    options: .init()
  )
  if let index = policy.bindings.firstIndex(where: { $0.role == role && $0.condition == nil }) {
    policy.bindings[index].members.removeAll(where: { $0 == member })
  }
  policy.bindings.removeAll(where: { $0.members.isEmpty })
  let updated = try await client.setIamPolicy(
    request: .init().with {
      $0.resource = "projects/_/buckets/\(bucketId)"
      $0.policy = policy
    },
    options: .init()
  )
  print("Removed \(member) with role \(role) from \(bucketId): \(updated)")
}
// [END storage_remove_bucket_iam_member]
