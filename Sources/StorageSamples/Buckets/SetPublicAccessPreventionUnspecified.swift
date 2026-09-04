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

// [START storage_set_public_access_prevention_unspecified]
import GoogleCloudStorage

public func setPublicAccessPreventionUnspecified(
  client: StorageControlClient, bucketId: String
) async throws {
  let bucket = try await client.getBucket(
    request: .init().with {
      $0.name = "projects/_/buckets/\(bucketId)"
    },
    options: .init()
  )
  let _ = try await client.updateBucket(
    request: .init().with {
      $0.bucket = bucket.with { bucket in
        bucket.iamConfig = .init().with { iamConfig in
          iamConfig.publicAccessPrevention = ""
        }
      }
      $0.ifMetagenerationMatch = bucket.metageneration
      $0.updateMask = .init(paths: ["iam_config.public_access_prevention"])
    },
    options: .init()
  )
  print("Public access prevention is unspecified for bucket \(bucketId)")
}
// [END storage_set_public_access_prevention_unspecified]
