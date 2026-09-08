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

// [START storage_control_managed_folder_get]
import GoogleCloudStorage

public func managedFolderGet(
  client: StorageControlClient, bucketId: String
) async throws {
  let managedFolderId = "example001"
  let folder = try await client.getManagedFolder(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)/managedFolders/\(managedFolderId)"
    },
    options: .init()
  )
  print("successfully retrieved managed folder metadata: \(folder)")
}
// [END storage_control_managed_folder_get]
