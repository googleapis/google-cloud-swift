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

import Foundation
import GoogleCloudStorage

/// The maximum length for a bucket ID.
fileprivate let bucketIdLength = 63

/// A common prefix for resource ids.
///
/// Where possible, we use this prefix for randomly generated resource ids.
fileprivate let prefix = "swift-sdk-testing-"
fileprivate let lowerCaseAlphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"

public func runBucketSamples(
  client: StorageControlClient, projectId: String, serviceAccount: String,
  bucketNames: inout [String]
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

  let ublaBucketId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(ublaBucketId)")
  print("creating bucket without uniform bucket-level access")
  let _ = try await client.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = ublaBucketId
      $0.bucket = .init().with { bucket in
        bucket.project = "projects/\(projectId)"
        bucket.iamConfig = .init().with { iamConfig in
          iamConfig.uniformBucketLevelAccess = .init().with { ubla in
            ubla.enabled = false
          }
        }
      }
    },
    options: .init()
  )

  print("running enableUniformBucketLevelAccess() sample")
  try await enableUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)
  print("running getUniformBucketLevelAccess() sample")
  try await getUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)
  print("running disableUniformBucketLevelAccess() sample")
  try await disableUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)

  print("running addBucketOwner() sample")
  try await addBucketOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running removeBucketOwner() sample")
  try await removeBucketOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running addBucketDefaultOwner() sample")
  try await addBucketDefaultOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running removeBucketDefaultOwner() sample")
  try await removeBucketDefaultOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)

  let iamBucketId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(iamBucketId)")
  print("creating bucket with uniform bucket-level access for IAM samples")
  let _ = try await client.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = iamBucketId
      $0.bucket = .init().with { bucket in
        bucket.project = "projects/\(projectId)"
        bucket.iamConfig = .init().with { iamConfig in
          iamConfig.uniformBucketLevelAccess = .init().with { ubla in
            ubla.enabled = true
          }
        }
      }
    },
    options: .init()
  )

  print("running addBucketIamMember() sample")
  try await addBucketIamMember(
    client: client, bucketId: iamBucketId, role: "roles/storage.objectViewer",
    member: "serviceAccount:\(serviceAccount)")
  print("running removeBucketIamMember() sample")
  try await removeBucketIamMember(
    client: client, bucketId: iamBucketId, role: "roles/storage.objectViewer",
    member: "serviceAccount:\(serviceAccount)")
  // Skip by default: internal Google policies prevent granting public access to buckets in test projects.
  if ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_ENABLE_PUBLIC_IAM"] == "true" {
    print("running setBucketPublicIam() sample")
    try await setBucketPublicIam(client: client, bucketId: iamBucketId)
  }
  print("running addBucketConditionalIamBinding() sample")
  try await addBucketConditionalIamBinding(
    client: client, bucketId: iamBucketId, serviceAccount: serviceAccount)
  print("running removeBucketConditionalIamBinding() sample")
  try await removeBucketConditionalIamBinding(client: client, bucketId: iamBucketId)
  print("running viewBucketIamMembers() sample")
  try await viewBucketIamMembers(client: client, bucketId: iamBucketId)
}

/// Generates a random bucket ID.
public func randomBucketId() -> String {
  assert(prefix.count < bucketIdLength)
  let length = bucketIdLength - prefix.count
  let suffix = String((0..<length).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}
