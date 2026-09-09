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

// [START storage_object_csek_to_cmek]
import Foundation
import GoogleCloudStorage

public func objectCsekToCmek(
  client: StorageControlClient, bucketId: String, objectName: String,
  csekKey: CustomerEncryptionKeyOptions, kmsKey: String
) async throws {
  guard let keyBytes = Data(base64Encoded: csekKey.keyBase64),
    let keyHashBytes = Data(base64Encoded: csekKey.keyHashBase64)
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
        $0.copySourceEncryptionAlgorithm = csekKey.algorithm.rawValue
        $0.copySourceEncryptionKeyBytes = keyBytes
        $0.copySourceEncryptionKeySha256Bytes = keyHashBytes
        $0.destinationBucket = "projects/_/buckets/\(bucketId)"
        $0.destinationName = objectName
        $0.destinationKmsKey = kmsKey
        if !token.isEmpty {
          $0.rewriteToken = token
        }
      }
    )
    token = response.rewriteToken
  } while !response.done

  print(
    "successfully rotated encryption key for object \(objectName) in bucket \(bucketId) from CSEK to CMEK: \(response)"
  )
}
// [END storage_object_csek_to_cmek]
