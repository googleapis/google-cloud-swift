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

// [START storage_copy_file_archived_generation]
import GoogleCloudStorage

public func copyFileArchivedGeneration(
  client: StorageControlClient, sourceBucketId: String, destBucketId: String,
  generation: Int64
) async throws {
  let sourceName = "object-generation-to-copy"
  let destName = "copied-object"

  var token = ""
  var response: RewriteResponse
  repeat {
    response = try await client.rewriteObject(
      request: .init().with {
        $0.sourceBucket = "projects/_/buckets/\(sourceBucketId)"
        $0.sourceObject = sourceName
        $0.sourceGeneration = generation
        $0.destinationBucket = "projects/_/buckets/\(destBucketId)"
        $0.destinationName = destName
        if !token.isEmpty {
          $0.rewriteToken = token
        }
      },
      options: .init()
    )
    token = response.rewriteToken
  } while !response.done

  print(
    "successfully copied \(sourceBucketId)/\(sourceName) to \(destBucketId)/\(destName): \(response)"
  )
}
// [END storage_copy_file_archived_generation]
