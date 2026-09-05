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

// [START storage_print_file_acl]
import GoogleCloudStorage

public func printFileAcl(
  client: StorageControlClient, bucketId: String
) async throws {
  let objectName = "object-to-read"
  let object = try await client.getObject(
    request: .init().with {
      $0.bucket = "projects/_/buckets/\(bucketId)"
      $0.object = objectName
      $0.readMask = .init(paths: ["*"])
    },
    options: .init()
  )

  print("Object \(objectName) in bucket \(bucketId) has the following ACL: \(object.acl)")
}
// [END storage_print_file_acl]
