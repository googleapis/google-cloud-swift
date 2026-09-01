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

// [START storage_list_files_with_prefix]
import GoogleCloudStorage

public func listFilesWithPrefix(
  client: StorageControlClient, bucketId: String
) async throws {
  let prefix = "prefixes/are-not-always/folders-"
  let objects = try client.listObjects(
    byItem: .init().with {
      $0.parent = "projects/_/buckets/\(bucketId)"
      $0.prefix = prefix
    },
    options: .init()
  )
  print("listing objects in bucket \(bucketId) with prefix \(prefix)")
  for try await object in objects {
    print(object)
  }
  print("DONE")
}
// [END storage_list_files_with_prefix]
