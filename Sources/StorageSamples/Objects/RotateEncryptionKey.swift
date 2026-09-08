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

// [START storage_rotate_encryption_key]
import Foundation
import GoogleCloudStorage

public func rotateEncryptionKey(
  client: StorageControlClient, bucketId: String, objectName: String,
  oldKey: CustomerEncryptionKeyOptions, newKey: CustomerEncryptionKeyOptions
) async throws {
  guard let oldKeyBytes = Data(base64Encoded: oldKey.keyBase64),
    let oldKeyHashBytes = Data(base64Encoded: oldKey.keyHashBase64),
    let newKeyBytes = Data(base64Encoded: newKey.keyBase64),
    let newKeyHashBytes = Data(base64Encoded: newKey.keyHashBase64)
  else {
    return
  }

  var token = ""
  var response: RewriteResponse
  repeat {
    response = try await client.rewriteObject(
      request: .init().with {
        $0.sourceBucket = "projects/_/buckets/\(bucketId)"
        $0.sourceObject = objectName
        $0.copySourceEncryptionAlgorithm = oldKey.algorithm.rawValue
        $0.copySourceEncryptionKeyBytes = oldKeyBytes
        $0.copySourceEncryptionKeySha256Bytes = oldKeyHashBytes
        $0.destinationBucket = "projects/_/buckets/\(bucketId)"
        $0.destinationName = objectName
        $0.commonObjectRequestParams = .init().with { params in
          params.encryptionAlgorithm = newKey.algorithm.rawValue
          params.encryptionKeyBytes = newKeyBytes
          params.encryptionKeySha256Bytes = newKeyHashBytes
        }
        if !token.isEmpty {
          $0.rewriteToken = token
        }
      },
      options: .init()
    )
    token = response.rewriteToken
  } while !response.done

  print("Rotated encryption key for object \(objectName) in bucket \(bucketId).")
}
// [END storage_rotate_encryption_key]
