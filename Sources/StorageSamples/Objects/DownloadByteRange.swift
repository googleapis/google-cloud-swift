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

// [START storage_download_byte_range]
import Foundation
import GoogleCloudStorage

public func downloadByteRange(
  client: StorageClient, bucketId: String, objectName: String, start: UInt64, end: UInt64
) async throws {
  let options = ReadObjectOptions().with {
    $0.range = .bounded(start...end)
  }
  let reader = client.readObject(
    from: "projects/_/buckets/\(bucketId)", object: objectName, options: options)

  var content = Data()
  for try await buffer in reader.body {
    content.append(buffer.data)
  }

  print(
    "Downloaded \(content.count) bytes from \(start) to \(end) of object \(objectName) in bucket \(bucketId)."
  )
}
// [END storage_download_byte_range]
