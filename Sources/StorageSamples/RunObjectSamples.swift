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

/// Cloud Storage rate limits object metadata updates to approximately 1 update per second per object.
/// Pacing consecutive update operations on the same object avoids `resourceExhausted` rate limit errors.
fileprivate func paceObjectUpdates() async throws {
  try await Task.sleep(nanoseconds: 1_200_000_000)
}

public func runObjectSamples(
  controlClient: StorageControlClient, dataClient: StorageClient, projectId: String,
  serviceAccount: String, bucketNames: inout [String]
) async throws {
  let id = randomBucketId()
  let name = "projects/_/buckets/\(id)"
  bucketNames.append(name)

  let _ = try await controlClient.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = id
      $0.bucket = .init().with {
        $0.project = "projects/\(projectId)"
      }
    },
    options: .init()
  )

  let sampleText = "how vexingly quick daft zebras jump\n"
  let sampleData = Data(sampleText.utf8)

  // Seed test objects
  _ = try await dataClient.upload(sampleData, to: id, as: "object-to-download.txt")
  _ = try await dataClient.upload(sampleData, to: id, as: "prefixes/are-not-always/folders-001")
  _ = try await dataClient.upload(sampleData, to: id, as: "prefixes/are-not-always/folders-002")
  _ = try await dataClient.upload(sampleData, to: id, as: "prefixes/are-not-always/folders-003")
  _ = try await dataClient.upload(sampleData, to: id, as: "uploaded-file.txt")
  _ = try await dataClient.upload(sampleData, to: id, as: "deleted-object-name")
  _ = try await dataClient.upload(sampleData, to: id, as: "object-to-read")
  _ = try await dataClient.upload(sampleData, to: id, as: "object-to-update")
  _ = try await dataClient.upload(sampleData, to: id, as: "update-storage-class")
  _ = try await dataClient.upload(sampleData, to: id, as: "object-with-contexts")

  let tempFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(
    "downloaded-file-\(UUID().uuidString).txt"
  ).path
  defer {
    try? FileManager.default.removeItem(atPath: tempFilePath)
  }

  print("running streamFileDownload() sample")
  try await streamFileDownload(client: dataClient, bucketId: id)
  print("running fileUploadFromMemory() sample")
  try await fileUploadFromMemory(client: dataClient, bucketId: id)
  print("running downloadFile() sample")
  try await downloadFile(
    client: dataClient, bucketId: id, objectName: "uploaded-file.txt", filePath: tempFilePath)
  print("running listFiles() sample")
  try await listFiles(client: controlClient, bucketId: id)
  print("running listFilesWithPrefix() sample")
  try await listFilesWithPrefix(client: controlClient, bucketId: id)
  print("running deleteFile() sample")
  try await deleteFile(client: controlClient, bucketId: id)

  print("running setMetadata() sample")
  try await setMetadata(client: controlClient, bucketId: id)
  print("running getMetadata() sample")
  try await getMetadata(client: controlClient, bucketId: id)

  print("running printFileAcl() sample")
  try await printFileAcl(client: controlClient, bucketId: id)
  print("running printFileAclForUser() sample")
  try await printFileAclForUser(client: controlClient, bucketId: id)

  print("running setEventBasedHold() sample")
  try await paceObjectUpdates()
  try await setEventBasedHold(client: controlClient, bucketId: id)
  print("running releaseEventBasedHold() sample")
  try await paceObjectUpdates()
  try await releaseEventBasedHold(client: controlClient, bucketId: id)

  print("running setTemporaryHold() sample")
  try await paceObjectUpdates()
  try await setTemporaryHold(client: controlClient, bucketId: id)
  print("running releaseTemporaryHold() sample")
  try await paceObjectUpdates()
  try await releaseTemporaryHold(client: controlClient, bucketId: id)

  print("running changeFileStorageClass() sample")
  try await changeFileStorageClass(client: controlClient, bucketId: id)

  print("running setObjectContexts() sample")
  try await setObjectContexts(client: controlClient, bucketId: id)
  print("running getObjectContexts() sample")
  try await getObjectContexts(client: controlClient, bucketId: id)

  // Create a separate bucket with ACLs enabled and object retention enabled for ACL and retention samples
  let retentionAclBucketId = randomBucketId()
  let retentionAclBucketName = "projects/_/buckets/\(retentionAclBucketId)"
  bucketNames.append(retentionAclBucketName)

  print("creating bucket with ACLs and object retention enabled")
  let _ = try await controlClient.createBucket(
    request: .init().with {
      $0.parent = "projects/_"
      $0.bucketId = retentionAclBucketId
      $0.bucket = .init().with { bucket in
        bucket.project = "projects/\(projectId)"
        bucket.iamConfig = .init().with { iamConfig in
          iamConfig.uniformBucketLevelAccess = .init().with { ubla in
            ubla.enabled = false
          }
        }
        bucket.objectRetention = .init().with { objRetention in
          objRetention.enabled = true
        }
      }
    },
    options: .init()
  )

  _ = try await dataClient.upload(
    sampleData, to: retentionAclBucketId, as: "object-to-update")

  print("running addFileOwner() sample")
  try await addFileOwner(
    client: controlClient, bucketId: retentionAclBucketId, user: serviceAccount)
  print("running removeFileOwner() sample")
  try await paceObjectUpdates()
  try await removeFileOwner(
    client: controlClient, bucketId: retentionAclBucketId, user: serviceAccount)

  print("running setObjectRetentionPolicy() sample")
  try await paceObjectUpdates()
  try await setObjectRetentionPolicy(
    client: controlClient, bucketId: retentionAclBucketId)
}
