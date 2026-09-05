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

// [START storage_add_file_owner]
import GoogleCloudStorage

public func addFileOwner(
  client: StorageControlClient, bucketId: String, user: String
) async throws {
  let objectName = "object-to-update"
  let object = try await client.getObject(
    request: .init().with {
      $0.bucket = "projects/_/buckets/\(bucketId)"
      $0.object = objectName
      $0.readMask = .init(paths: ["*"])
    },
    options: .init()
  )
  let want = "user-\(user)"
  var acl = object.acl
  if let index = acl.firstIndex(where: { $0.entity == want }) {
    acl[index].role = "OWNER"
  } else {
    acl.append(
      ObjectAccessControl().with { entry in
        entry.entity = want
        entry.role = "OWNER"
      }
    )
  }
  let updated = try await client.updateObject(
    request: .init().with {
      $0.object = object.with { obj in
        obj.acl = acl
      }
      $0.ifMetagenerationMatch = object.metageneration
      $0.updateMask = .init(paths: ["acl"])
    },
    options: .init()
  )
  print("successfully updated object \(objectName) in bucket \(bucketId): \(updated)")
}
// [END storage_add_file_owner]
