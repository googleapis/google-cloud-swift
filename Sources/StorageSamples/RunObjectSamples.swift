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

public func runObjectSamples(
  controlClient: StorageControlClient, dataClient: StorageClient, projectId: String,
  bucketNames: inout [String]
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
}
