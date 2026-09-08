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

// [START storage_stream_file_upload]
import Foundation
import GoogleCloudStorage

public func streamFileUpload(
  client: StorageClient, bucketId: String
) async throws {
  let objectName = "object-to-upload.txt"
  let stream = AsyncStream<Data> { continuation in
    for i in (1...100).reversed() {
      continuation.yield(Data("still have to send \(i) lines\n".utf8))
    }
    continuation.finish()
  }
  let source = StreamSource(sequence: stream)
  let object = try await client.upload(source, to: bucketId, as: objectName)
  print("successfully uploaded object \(objectName) to bucket \(bucketId): \(object)")
}
// [END storage_stream_file_upload]
