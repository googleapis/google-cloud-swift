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

// [START storage_upload_with_kms_key]
import Foundation
import GoogleCloudStorage

public func uploadWithKmsKey(
  client: StorageClient, bucketId: String, filePath: String, kmsKey: String
) async throws {
  let objectName = "object-to-upload.txt"
  let fileURL = URL(fileURLWithPath: filePath)
  let options = UploadOptions().with {
    $0.kmsKeyName = kmsKey
  }
  let _ = try await client.upload(
    fileURL,
    to: bucketId,
    as: objectName,
    options: options
  )
  print("Uploaded \(objectName) to bucket \(bucketId) with KMS key \(kmsKey).")
}
// [END storage_upload_with_kms_key]
