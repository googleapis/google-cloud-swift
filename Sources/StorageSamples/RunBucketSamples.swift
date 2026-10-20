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
  kmsRing: String? = nil, bucketNames: inout [String]
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

  let quickstartId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(quickstartId)")
  print("running quickstart() sample")
  try await quickstart(client: client, projectId: projectId, bucketId: quickstartId)

  let classLocationId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(classLocationId)")
  print("running createBucketClassLocation() sample")
  try await createBucketClassLocation(
    client: client, projectId: projectId, bucketId: classLocationId)
  print("running getBucketClassAndLocation() sample")
  try await getBucketClassAndLocation(client: client, bucketId: classLocationId)
  print("running getBucketMetadata() sample")
  try await getBucketMetadata(client: client, bucketId: classLocationId)

  let dualRegionId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(dualRegionId)")
  print("running createBucketDualRegion() sample")
  try await createBucketDualRegion(client: client, projectId: projectId, bucketId: dualRegionId)
  print("running getRpo() sample")
  try await getRpo(client: client, bucketId: dualRegionId)
  print("running setRpoDefault() sample")
  try await setRpoDefault(client: client, bucketId: dualRegionId)
  print("running setRpoAsyncTurbo() sample")
  try await setRpoAsyncTurbo(client: client, bucketId: dualRegionId)

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
  print("running setBucketEncryptionEnforcement() sample")
  try await setBucketEncryptionEnforcement(
    client: client, bucketId: encryptionEnforcementId)

  let objectRetentionId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(objectRetentionId)")
  print("running createBucketWithObjectRetention() sample")
  try await createBucketWithObjectRetention(
    client: client, projectId: projectId, bucketId: objectRetentionId)

  // Create a separate Standard bucket for Autoclass and Requester Pays samples, as Autoclass
  // cannot be enabled after changing the default storage class to NEARLINE.
  let autoclassBucketId = randomBucketId()
  bucketNames.append("projects/_/buckets/\(autoclassBucketId)")
  print("creating bucket for autoclass and requester pays samples")
  let _ = try await client.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = autoclassBucketId
      $0.bucket = .init().with { bucket in
        bucket.project = "projects/\(projectId)"
      }
    }
  )
  print("running setAutoclass() sample")
  try await setAutoclass(client: client, bucketId: autoclassBucketId)
  print("running getAutoclass() sample")
  try await getAutoclass(client: client, bucketId: autoclassBucketId)
  print("running enableRequesterPays() sample")
  try await enableRequesterPays(client: client, bucketId: autoclassBucketId)
  print("running getRequesterPaysStatus() sample")
  try await getRequesterPaysStatus(client: client, bucketId: autoclassBucketId)
  print("running disableRequesterPays() sample")
  try await disableRequesterPays(client: client, bucketId: autoclassBucketId)
  print("running getRequesterPaysStatus() sample")
  try await getRequesterPaysStatus(client: client, bucketId: autoclassBucketId)

  // Reuse a single bucket across compatible metadata, lifecycle, retention, UBLA, and ACL samples
  // to reduce project-wide CreateBucket quota pressure.
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
    }
  )

  print("running changeDefaultStorageClass() sample")
  try await changeDefaultStorageClass(
    client: client, bucketId: ublaBucketId, storageClass: "NEARLINE")
  print("running addBucketLabel() sample")
  try await addBucketLabel(
    client: client, bucketId: ublaBucketId, labelKey: "test-label", labelValue: "test-value")
  print("running getBucketLabels() sample")
  try await getBucketLabels(client: client, bucketId: ublaBucketId)
  print("running removeBucketLabel() sample")
  try await removeBucketLabel(
    client: client, bucketId: ublaBucketId, labelKey: "test-label")

  print("running getDefaultEventBasedHold() sample")
  try await getDefaultEventBasedHold(client: client, bucketId: ublaBucketId)
  print("running enableDefaultEventBasedHold() sample")
  try await enableDefaultEventBasedHold(client: client, bucketId: ublaBucketId)
  print("running disableDefaultEventBasedHold() sample")
  try await disableDefaultEventBasedHold(client: client, bucketId: ublaBucketId)
  print("running setPublicAccessPreventionUnspecified() sample")
  try await setPublicAccessPreventionUnspecified(client: client, bucketId: ublaBucketId)
  print("running setPublicAccessPreventionInherited() sample")
  try await setPublicAccessPreventionInherited(client: client, bucketId: ublaBucketId)
  print("running getPublicAccessPrevention() sample")
  try await getPublicAccessPrevention(client: client, bucketId: ublaBucketId)
  print("running setPublicAccessPreventionEnforced() sample")
  try await setPublicAccessPreventionEnforced(client: client, bucketId: ublaBucketId)

  print("running enableUniformBucketLevelAccess() sample")
  try await enableUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)
  print("running getUniformBucketLevelAccess() sample")
  try await getUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)
  print("running disableUniformBucketLevelAccess() sample")
  try await disableUniformBucketLevelAccess(client: client, bucketId: ublaBucketId)

  print("running viewVersioningStatus() sample")
  try await viewVersioningStatus(client: client, bucketId: ublaBucketId)
  print("running enableVersioning() sample")
  try await enableVersioning(client: client, bucketId: ublaBucketId)
  print("running disableVersioning() sample")
  try await disableVersioning(client: client, bucketId: ublaBucketId)
  print("running viewLifecycleManagementConfiguration() sample")
  try await viewLifecycleManagementConfiguration(client: client, bucketId: ublaBucketId)
  print("running enableBucketLifecycleManagement() sample")
  try await enableBucketLifecycleManagement(client: client, bucketId: ublaBucketId)
  print("running addLifecycleRule() sample")
  try await addLifecycleRule(client: client, bucketId: ublaBucketId)
  print("running disableBucketLifecycleManagement() sample")
  try await disableBucketLifecycleManagement(client: client, bucketId: ublaBucketId)

  print("running printBucketWebsiteConfiguration() sample")
  try await printBucketWebsiteConfiguration(client: client, bucketId: ublaBucketId)
  print("running defineBucketWebsiteConfiguration() sample")
  try await defineBucketWebsiteConfiguration(
    client: client, bucketId: ublaBucketId, mainPageSuffix: "index.html",
    notFoundPage: "404.html")
  print("running corsConfiguration() sample")
  try await corsConfiguration(
    client: client, bucketId: ublaBucketId, maxAgeSeconds: 3600,
    method: ["GET", "HEAD"], origin: ["http://example.com"],
    responseHeader: ["Content-Type"])
  print("running removeCorsConfiguration() sample")
  try await removeCorsConfiguration(client: client, bucketId: ublaBucketId)
  print("running removeRetentionPolicy() sample")
  try await removeRetentionPolicy(client: client, bucketId: ublaBucketId)
  print("running setRetentionPolicy() sample")
  try await setRetentionPolicy(
    client: client, bucketId: ublaBucketId, retentionPeriod: 60)
  print("running getRetentionPolicy() sample")
  try await getRetentionPolicy(client: client, bucketId: ublaBucketId)
  print("running lockRetentionPolicy() sample")
  try await lockRetentionPolicy(client: client, bucketId: ublaBucketId)

  print("running addBucketOwner() sample")
  try await addBucketOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running printBucketAcl() sample")
  try await printBucketAcl(client: client, bucketId: ublaBucketId)
  print("running printBucketAclForUser() sample")
  try await printBucketAclForUser(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  try await printBucketAclForUser(
    client: client, bucketId: ublaBucketId, userEmail: "test-user-not-found@example.com")
  print("running removeBucketOwner() sample")
  try await removeBucketOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running addBucketDefaultOwner() sample")
  try await addBucketDefaultOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)
  print("running removeBucketDefaultOwner() sample")
  try await removeBucketDefaultOwner(
    client: client, bucketId: ublaBucketId, userEmail: serviceAccount)

  // Reuse the hierarchical namespace bucket (which has uniform bucket-level access enabled)
  // for IAM policy samples.
  print("running addBucketIamMember() sample")
  try await addBucketIamMember(
    client: client, bucketId: hierarchicalNamespaceId, role: "roles/storage.objectViewer",
    member: "serviceAccount:\(serviceAccount)")
  print("running removeBucketIamMember() sample")
  try await removeBucketIamMember(
    client: client, bucketId: hierarchicalNamespaceId, role: "roles/storage.objectViewer",
    member: "serviceAccount:\(serviceAccount)")
  // Skip by default: internal Google policies prevent granting public access to buckets in test projects.
  if ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_ENABLE_PUBLIC_IAM"] == "true" {
    print("running setBucketPublicIam() sample")
    try await setBucketPublicIam(client: client, bucketId: hierarchicalNamespaceId)
  }
  print("running addBucketConditionalIamBinding() sample")
  try await addBucketConditionalIamBinding(
    client: client, bucketId: hierarchicalNamespaceId, serviceAccount: serviceAccount)
  print("running removeBucketConditionalIamBinding() sample")
  try await removeBucketConditionalIamBinding(client: client, bucketId: hierarchicalNamespaceId)
  print("running viewBucketIamMembers() sample")
  try await viewBucketIamMembers(client: client, bucketId: hierarchicalNamespaceId)

  if let kmsRing = kmsRing {
    let kmsBucketId = randomBucketId()
    bucketNames.append("projects/_/buckets/\(kmsBucketId)")
    print("creating bucket for KMS tests")
    let _ = try await client.createBucket(
      request: .init().with {
        $0.parent = "projects/_"
        $0.bucketId = kmsBucketId
        $0.bucket = .init().with { bucket in
          bucket.project = "projects/\(projectId)"
          bucket.location = "US-CENTRAL1"
        }
      }
    )
    let kmsKey =
      "projects/\(projectId)/locations/us-central1/keyRings/\(kmsRing)/cryptoKeys/storage-examples"
    print("running setBucketDefaultKmsKey() sample")
    try await setBucketDefaultKmsKey(client: client, bucketId: kmsBucketId, kmsKey: kmsKey)
    print("running getBucketDefaultKmsKey() sample")
    try await getBucketDefaultKmsKey(client: client, bucketId: kmsBucketId)
    print("running deleteBucketDefaultKmsKey() sample")
    try await deleteBucketDefaultKmsKey(client: client, bucketId: kmsBucketId)
  }
}

/// Generates a random bucket ID.
public func randomBucketId() -> String {
  assert(prefix.count < bucketIdLength)
  let length = bucketIdLength - prefix.count
  let suffix = String((0..<length).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}
