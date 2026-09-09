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

import Foundation
import GoogleCloudStorage

public func runControlSamples(
  client: StorageControlClient, projectId: String, zone: String, bucketNames: inout [String]
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
    }
  )

  print("running quickstartSample() sample")
  try await quickstartSample(client: client, bucketId: id)
  print("running managedFolderCreate() sample")
  try await managedFolderCreate(client: client, bucketId: id)
  print("running managedFolderGet() sample")
  try await managedFolderGet(client: client, bucketId: id)
  print("running managedFolderList() sample")
  try await managedFolderList(client: client, bucketId: id)
  print("running managedFolderDelete() sample")
  try await managedFolderDelete(client: client, bucketId: id)
  print("running listAnywhereCaches() sample")
  try await listAnywhereCaches(client: client, bucketId: id)
  print("running createAnywhereCache() sample")
  try await createAnywhereCache(client: client, bucketId: id, zone: zone)
  print("running getAnywhereCache() sample")
  try await getAnywhereCache(client: client, bucketId: id, cacheId: zone)
  print("running pauseAnywhereCache() sample")
  try await pauseAnywhereCache(client: client, bucketId: id, cacheId: zone)
  print("running resumeAnywhereCache() sample")
  try await resumeAnywhereCache(client: client, bucketId: id, cacheId: zone)
  print("running updateAnywhereCache() sample")
  try await updateAnywhereCache(client: client, bucketId: id, cacheId: zone)
  print("running disableAnywhereCache() sample")
  try await disableAnywhereCache(client: client, bucketId: id, cacheId: zone)
}
