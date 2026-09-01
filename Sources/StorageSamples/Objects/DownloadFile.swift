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

// [START storage_download_file]
import Foundation
import GoogleCloudStorage

public func downloadFile(
  client: StorageClient, bucketId: String, objectName: String, filePath: String
) async throws {
  let reader = client.readObject(from: "projects/_/buckets/\(bucketId)", object: objectName)
  if !FileManager.default.createFile(atPath: filePath, contents: nil) {
    throw POSIXError(.EEXIST)
  }
  let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
  defer {
    try? fileHandle.close()
  }

  for try await buffer in reader.body {
    try fileHandle.write(contentsOf: buffer.data)
  }

  print("Downloaded \(objectName) in bucket \(bucketId) to \(filePath).")
}
// [END storage_download_file]
