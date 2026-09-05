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

// [START storage_set_temporary_hold]
import GoogleCloudStorage

public func setTemporaryHold(
  client: StorageControlClient, bucketId: String
) async throws {
  let objectName = "object-to-update"
  let object = try await client.getObject(
    request: .init().with {
      $0.bucket = "projects/_/buckets/\(bucketId)"
      $0.object = objectName
    },
    options: .init()
  )

  let updated = try await client.updateObject(
    request: .init().with {
      $0.object = object.with { obj in
        obj.temporaryHold = true
      }
      $0.ifMetagenerationMatch = object.metageneration
      $0.updateMask = .init(paths: ["temporary_hold"])
    },
    options: .init()
  )
  print(
    "successfully set temporary hold on object \(objectName) in bucket \(bucketId): \(updated)"
  )
}
// [END storage_set_temporary_hold]
