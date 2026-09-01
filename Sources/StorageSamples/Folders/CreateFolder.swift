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

// [START storage_control_create_folder]
import GoogleCloudStorage

public func createFolder(
  client: StorageControlClient, bucketId: String
) async throws {
  let folderId = "example-folder-id"
  let folder = try await client.createFolder(
    request: .init().with {
      $0.parent = "projects/_/buckets/\(bucketId)"
      $0.folderId = folderId
      $0.folder = .init()
    },
    options: .init()
  )
  print("folder successfully created \(folder)")
}
// [END storage_control_create_folder]
