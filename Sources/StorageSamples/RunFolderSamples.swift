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

import GoogleCloudStorage

public func runFolderSamples(
  client: StorageControlClient, projectId: String, bucketNames: inout [String]
) async throws {
  let id = randomBucketId()
  let name = "projects/_/buckets/\(id)"
  bucketNames.append(name)

  let _ = try await client.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = id
      $0.bucket = .init().with {
        $0.project = "projects/\(projectId)"
        $0.hierarchicalNamespace = .init().with {
          $0.enabled = true
        }
        $0.iamConfig = .init().with {
          $0.uniformBucketLevelAccess = .init().with {
            $0.enabled = true
          }
        }
      }
    },
    options: .init()
  )

  // Seed a folder for deleteFolder to delete
  let _ = try await client.createFolder(
    request: .init().with {
      $0.parent = name
      $0.folderId = "deleted-folder-id"
      $0.folder = .init()
    },
    options: .init()
  )

  print("running createFolder() sample")
  try await createFolder(client: client, bucketId: id)
  print("running getFolder() sample")
  try await getFolder(client: client, bucketId: id)
  print("running listFolders() sample")
  try await listFolders(client: client, bucketId: id)
  // TODO(https://github.com/googleapis/google-cloud-swift/issues/594) - enable
  // print("running renameFolder() sample")
  // try await renameFolder(client: client, bucketId: id)
  print("running deleteFolder() sample")
  try await deleteFolder(client: client, bucketId: id)
}
