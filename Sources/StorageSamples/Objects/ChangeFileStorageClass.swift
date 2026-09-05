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

// [START storage_change_file_storage_class]
import GoogleCloudStorage

public func changeFileStorageClass(
  client: StorageControlClient, bucketId: String
) async throws {
  let objectName = "update-storage-class"
  var token = ""
  var response: RewriteResponse
  repeat {
    response = try await client.rewriteObject(
      request: .init().with {
        $0.sourceBucket = "projects/_/buckets/\(bucketId)"
        $0.sourceObject = objectName
        $0.destinationBucket = "projects/_/buckets/\(bucketId)"
        $0.destinationName = objectName
        // For other valid storage classes, refer to the documentation:
        // https://cloud.google.com/storage/docs/storage-classes
        $0.destination = .init().with { dest in
          dest.storageClass = "NEARLINE"
        }
        if !token.isEmpty {
          $0.rewriteToken = token
        }
      },
      options: .init()
    )
    token = response.rewriteToken
  } while !response.done

  print(
    "successfully updated storage class for object \(objectName) in bucket \(bucketId): \(response)"
  )
}
// [END storage_change_file_storage_class]
