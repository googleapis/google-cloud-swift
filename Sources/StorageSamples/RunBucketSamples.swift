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

/// The maximum length for a bucket ID.
fileprivate let bucketIdLength = 63

/// A common prefix for resource ids.
///
/// Where possible, we use this prefix for randomly generated resource ids.
fileprivate let prefix = "swift-sdk-testing-"
fileprivate let lowerCaseAlphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"

public func runBucketSamples(
  client: StorageControlClient, projectId: String, bucketNames: inout [String]
) async throws {
  let id = randomBucketId()
  let name = "projects/_/buckets/\(id)"
  bucketNames.append(name)

  print("running createBucket() sample")
  try await createBucket(client: client, projectId: projectId, bucketId: id)
  print("running deleteBucket() sample")
  try await deleteBucket(client: client, projectId: projectId, bucketId: id)
}

/// Generates a random bucket ID.
public func randomBucketId() -> String {
  assert(prefix.count < bucketIdLength)
  let length = bucketIdLength - prefix.count
  let suffix = String((0..<length).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}
