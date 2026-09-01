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
  print("running listBuckets() sample")
  try await listBuckets(client: client, projectId: projectId)
  print("running deleteBucket() sample")
  try await deleteBucket(client: client, projectId: projectId, bucketId: id)

  let classLocationId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(classLocationId)")
  print("running createBucketClassLocation() sample")
  try await createBucketClassLocation(
    client: client, projectId: projectId, bucketId: classLocationId)

  let dualRegionId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(dualRegionId)")
  print("running createBucketDualRegion() sample")
  try await createBucketDualRegion(client: client, projectId: projectId, bucketId: dualRegionId)

  let turboReplicationId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(turboReplicationId)")
  print("running createBucketTurboReplication() sample")
  try await createBucketTurboReplication(
    client: client, projectId: projectId, bucketId: turboReplicationId)

  let hierarchicalNamespaceId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(hierarchicalNamespaceId)")
  print("running createBucketHierarchicalNamespace() sample")
  try await createBucketHierarchicalNamespace(
    client: client, projectId: projectId, bucketId: hierarchicalNamespaceId)

  let encryptionEnforcementId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(encryptionEnforcementId)")
  print("running createBucketWithEncryptionEnforcement() sample")
  try await createBucketWithEncryptionEnforcement(
    client: client, projectId: projectId, bucketId: encryptionEnforcementId)

  let objectRetentionId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(objectRetentionId)")
  print("running createBucketWithObjectRetention() sample")
  try await createBucketWithObjectRetention(
    client: client, projectId: projectId, bucketId: objectRetentionId)
}

/// Generates a random bucket ID.
public func randomBucketId() -> String {
  assert(prefix.count < bucketIdLength)
  let length = bucketIdLength - prefix.count
  let suffix = String((0..<length).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}
