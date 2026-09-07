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

// [START storage_compose_file]
import GoogleCloudStorage

public func composeFile(
  client: StorageControlClient, bucketId: String
) async throws {
  let composeSource1 = "compose-source-object-1"
  let composeSource2 = "compose-source-object-2"
  let destinationName = "compose-destination-object"

  let object = try await client.composeObject(
    request: .init().with {
      $0.destination = .init().with { dest in
        dest.bucket = "projects/_/buckets/\(bucketId)"
        dest.name = destinationName
      }
      $0.sourceObjects = [
        .init().with { source in
          source.name = composeSource1
        },
        .init().with { source in
          source.name = composeSource2
        },
      ]
      // Consider setting generation to make request idempotent
      // Consider setting deleteSourceObjects to automatically delete the source objects
    },
    options: .init()
  )
  print("successfully composed \(composeSource1) and \(composeSource2) into object \(object)")
}
// [END storage_compose_file]
