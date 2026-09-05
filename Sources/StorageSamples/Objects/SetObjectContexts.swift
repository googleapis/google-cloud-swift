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

// [START storage_set_object_contexts]
import GoogleCloudStorage

public func setObjectContexts(
  client: StorageControlClient, bucketId: String
) async throws {
  let objectName = "object-with-contexts"
  let object = try await client.getObject(
    request: .init().with {
      $0.bucket = "projects/_/buckets/\(bucketId)"
      $0.object = objectName
    },
    options: .init()
  )

  var custom = object.contexts?.custom ?? [:]
  custom["example"] = ObjectCustomContextPayload().with { payload in
    payload.value = "true"
  }

  let updated = try await client.updateObject(
    request: .init().with {
      $0.object = object.with { obj in
        obj.contexts = ObjectContexts().with { contexts in
          contexts.custom = custom
        }
      }
      $0.ifMetagenerationMatch = object.metageneration
      $0.updateMask = .init(paths: ["contexts.custom.example"])
    },
    options: .init()
  )
  print(
    "successfully set contexts for object \(objectName) in bucket \(bucketId): \(String(describing: updated.contexts))"
  )
}
// [END storage_set_object_contexts]
