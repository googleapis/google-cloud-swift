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

// [START storage_set_client_endpoint]
import GoogleCloudGax
import GoogleCloudStorage

public func setClientEndpoint(bucketId: String) async throws {
  let objectName = "hello-world.txt"
  let client = try StorageClient(
    StorageClientOptions().with {
      $0.client.endpoint = "https://storage.googleapis.com"
    }
  )
  // Use the `StorageClient` as usual:
  let reader = client.readObject(
    from: "projects/_/buckets/\(bucketId)",
    object: objectName
  )
  let metadata = try await reader.metadata
  print("Object highlights: \(metadata)")

  let control = try StorageControlClient(
    ClientOptions().with {
      $0.endpoint = "https://storage.googleapis.com"
    }
  )
  // Use the `StorageControlClient` as usual:
  let bucket = try await control.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  print("Bucket \(bucketId) metadata is \(bucket)")
}
// [END storage_set_client_endpoint]
