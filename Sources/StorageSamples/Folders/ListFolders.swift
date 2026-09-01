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

// [START storage_control_list_folders]
import GoogleCloudStorage

public func listFolders(
  client: StorageControlClient, bucketId: String
) async throws {
  let folders = try client.listFolders(
    byItem: .init().with {
      $0.parent = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  print("listing folders in bucket \(bucketId)")
  for try await folder in folders {
    print(folder)
  }
  print("DONE")
}
// [END storage_control_list_folders]
