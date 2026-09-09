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

// [START storage_configure_retries]
import GoogleCloudGax
import GoogleCloudStorage

public func configureRetries(bucketId: String) async throws {
  // Retries all operations for up to 5 minutes, including any backoff time.
  let retryPolicy = StorageBaseRetryPolicy().withTimeLimit(.seconds(5 * 60))
  // On error, it backs off for a random delay between [0, 1] seconds, then
  // [0, 3] seconds, then [0, 9] seconds, etc. The backoff time never grows
  // larger than 1 minute.
  let backoffPolicy = try ExponentialBackoff(
    config: ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(1)
      $0.maximumDelay = .seconds(60)
      $0.scaling = 3.0
    }
  )

  let control = try StorageControlClient(
    ClientOptions().with {
      $0.retryPolicy = retryPolicy
      $0.backoffPolicy = backoffPolicy
    }
  )
  // Use the `StorageControlClient` as usual:
  let bucket = try await control.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    }
  )
  print("Bucket \(bucketId) metadata is \(bucket)")

  // Retries all operations for up to 5 attempts.
  let dataRetryPolicy = StorageBaseRetryPolicy().withAttemptLimit(5)
  // On error, it backs off for a random delay between [0, 1] seconds, then
  // [0, 3] seconds, then [0, 9] seconds, etc. The backoff time never grows
  // larger than 1 minute.
  let dataBackoffPolicy = try ExponentialBackoff(
    config: ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(1)
      $0.maximumDelay = .seconds(60)
      $0.scaling = 3.0
    }
  )

  let objectName = "hello-world.txt"
  let client = try StorageClient(
    StorageClientOptions().with {
      $0.client.retryPolicy = dataRetryPolicy
      $0.client.backoffPolicy = dataBackoffPolicy
    }
  )
  // Use the `StorageClient` as usual:
  let reader = client.readObject(
    from: "projects/_/buckets/\(bucketId)",
    object: objectName
  )
  let metadata = try await reader.metadata
  print("Object highlights: \(metadata)")
}
// [END storage_configure_retries]
