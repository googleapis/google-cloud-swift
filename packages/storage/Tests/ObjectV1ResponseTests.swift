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
@_spi(GoogleCloudInternal) import GoogleCloudWkt
@testable import GoogleCloudStorage
import Testing

@Suite struct ObjectV1ResponseTests {
  @Test func emptyAndDefaultValues() throws {
    let jsonString = "{}"
    let data = try #require(jsonString.data(using: .utf8))

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.name == "")
    #expect(object.bucket == "")
    #expect(object.etag == "")
    #expect(object.generation == 0)
    #expect(object.restoreToken == nil)
    #expect(object.metageneration == 0)
    #expect(object.storageClass == "")
    #expect(object.size == 0)
    #expect(object.contentEncoding == "")
    #expect(object.contentDisposition == "")
    #expect(object.cacheControl == "")
    #expect(object.acl.isEmpty)
    #expect(object.contentLanguage == "")
    #expect(object.deleteTime == nil)
    #expect(object.finalizeTime == nil)
    #expect(object.contentType == "")
    #expect(object.createTime == nil)
    #expect(object.componentCount == 0)
    #expect(object.checksums == nil)
    #expect(object.updateTime == nil)
    #expect(object.kmsKey == "")
    #expect(object.updateStorageClassTime == nil)
    #expect(object.temporaryHold == false)
    #expect(object.retentionExpireTime == nil)
    #expect(object.metadata.isEmpty)
    #expect(object.contexts == nil)
    #expect(object.eventBasedHold == nil)
    #expect(object.owner == nil)
    #expect(object.customerEncryption == nil)
    #expect(object.customTime == nil)
    #expect(object.softDeleteTime == nil)
    #expect(object.hardDeleteTime == nil)
    #expect(object.retention == nil)
  }

  @Test func allFieldsPopulatedFromJSON() throws {
    let jsonString = """
      {
        "name": "photos/image.png",
        "bucket": "my-bucket",
        "etag": "etag-12345",
        "generation": "1234567890",
        "metageneration": "3",
        "storageClass": "STANDARD",
        "size": "2048",
        "contentEncoding": "gzip",
        "contentDisposition": "inline",
        "cacheControl": "max-age=3600",
        "acl": [
          {
            "role": "OWNER",
            "entity": "user-test@example.com",
            "entityId": "user-id-1"
          },
          {
            "role": "READER",
            "entity": "allUsers"
          }
        ],
        "contentLanguage": "en",
        "contentType": "image/png",
        "timeCreated": "2026-01-01T00:00:03Z",
        "componentCount": "4",
        "crc32c": "AAAAAA==",
        "md5Hash": "1B2M2Y8AsgTpgAmY7PhCfg==",
        "updated": "2026-01-01T00:00:04Z",
        "kmsKeyName": "projects/p/locations/l/keyRings/r/cryptoKeys/k",
        "timeStorageClassUpdated": "2026-01-01T00:00:05Z",
        "temporaryHold": true,
        "retentionExpirationTime": "2027-01-01T00:00:00Z",
        "metadata": {
          "custom-key": "custom-value",
          "author": "swift-sdk"
        },
        "contexts": {
          "custom": {
            "classification": {
              "value": "confidential"
            }
          }
        },
        "eventBasedHold": true,
        "owner": {
          "entity": "user-owner@example.com",
          "entityId": "owner-123"
        },
        "customerEncryption": {
          "encryptionAlgorithm": "AES256"
        },
        "customTime": "2026-06-01T00:00:00Z",
        "retention": {
          "mode": "Unlocked",
          "retainUntilTime": "2028-01-01T00:00:00Z"
        }
      }
      """
    let data = try #require(jsonString.data(using: .utf8))

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.name == "photos/image.png")
    #expect(object.bucket == "projects/_/buckets/my-bucket")
    #expect(object.etag == "etag-12345")
    #expect(object.generation == 1234567890)
    #expect(object.metageneration == 3)
    #expect(object.storageClass == "STANDARD")
    #expect(object.size == 2048)
    #expect(object.contentEncoding == "gzip")
    #expect(object.contentDisposition == "inline")
    #expect(object.cacheControl == "max-age=3600")

    #expect(object.acl.count == 2)
    #expect(object.acl[0].role == "OWNER")
    #expect(object.acl[0].entity == "user-test@example.com")
    #expect(object.acl[0].entityId == "user-id-1")
    #expect(object.acl[1].role == "READER")
    #expect(object.acl[1].entity == "allUsers")

    #expect(object.contentLanguage == "en")
    #expect(object.contentType == "image/png")
    #expect(object.createTime != nil)
    #expect(object.componentCount == 4)

    #expect(object.checksums != nil)
    #expect(object.checksums?.crc32C == 0)
    #expect(object.checksums?.md5Hash == Data(base64Encoded: "1B2M2Y8AsgTpgAmY7PhCfg=="))

    #expect(object.updateTime != nil)
    #expect(object.kmsKey == "projects/p/locations/l/keyRings/r/cryptoKeys/k")
    #expect(object.updateStorageClassTime != nil)
    #expect(object.temporaryHold == true)
    #expect(object.retentionExpireTime != nil)

    #expect(object.metadata["custom-key"] == "custom-value")
    #expect(object.metadata["author"] == "swift-sdk")

    #expect(object.contexts?.custom["classification"]?.value == "confidential")
    #expect(object.eventBasedHold == true)

    #expect(object.owner?.entity == "user-owner@example.com")
    #expect(object.owner?.entityId == "owner-123")

    #expect(object.customerEncryption?.encryptionAlgorithm == "AES256")
    #expect(object.customTime != nil)

    #expect(object.retention?.mode == .unlocked)
    #expect(object.retention?.retainUntilTime != nil)
  }

  @Test func numericFieldsAsIntegers() throws {
    let jsonString = """
      {
        "generation": 9876543210,
        "metageneration": 42,
        "size": 1048576,
        "componentCount": 16
      }
      """
    let data = try #require(jsonString.data(using: .utf8))

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.generation == 9876543210)
    #expect(object.metageneration == 42)
    #expect(object.size == 1048576)
    #expect(object.componentCount == 16)
  }

  @Test func numericFieldsAsStrings() throws {
    let jsonString = """
      {
        "generation": "9876543210",
        "metageneration": "42",
        "size": "1048576",
        "componentCount": "16"
      }
      """
    let data = try #require(jsonString.data(using: .utf8))

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.generation == 9876543210)
    #expect(object.metageneration == 42)
    #expect(object.size == 1048576)
    #expect(object.componentCount == 16)
  }

  @Test func numericFieldsWithInvalidValuesDefaultToZero() throws {
    let jsonString = """
      {
        "generation": "invalid_number",
        "metageneration": "not_an_int",
        "size": "bad_size",
        "componentCount": "invalid_count"
      }
      """
    let data = try #require(jsonString.data(using: .utf8))

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.generation == 0)
    #expect(object.metageneration == 0)
    #expect(object.size == 0)
    #expect(object.componentCount == 0)
  }

  @Test(arguments: [
    (Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString(), UInt32(0x1234_5678)),
    ("305419896", UInt32(305_419_896)),
    ("AAAAAA==", UInt32(0)),
    (Data([0xFF, 0xFF, 0xFF, 0xFF]).base64EncodedString(), UInt32(0xFFFF_FFFF)),
  ])
  func crc32cChecksumVariants(crc32cInput: String, expectedValue: UInt32) throws {
    let json = """
      {
        "crc32c": "\(crc32cInput)"
      }
      """
    let data = try #require(json.data(using: .utf8))
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.checksums?.crc32C == expectedValue)
  }

  @Test func md5HashChecksumConversions() throws {
    // Valid 16-byte base64 MD5 hash
    let rawMD5 = Data(repeating: 0xAB, count: 16)
    let base64MD5 = rawMD5.base64EncodedString()
    let json = """
      {
        "md5Hash": "\(base64MD5)"
      }
      """
    let data = try #require(json.data(using: .utf8))
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.checksums != nil)
    #expect(object.checksums?.md5Hash == rawMD5)
    #expect(object.checksums?.crc32C == nil)
  }

  @Test func noChecksumsWhenOmitted() throws {
    let json = """
      {
        "name": "file.txt"
      }
      """
    let data = try #require(json.data(using: .utf8))
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.checksums == nil)
  }

  @Test(arguments: [
    ("unlocked", Object.Retention.Mode.unlocked),
    ("UNLOCKED", Object.Retention.Mode.unlocked),
    ("Unlocked", Object.Retention.Mode.unlocked),
    ("locked", Object.Retention.Mode.locked),
    ("LOCKED", Object.Retention.Mode.locked),
    ("Locked", Object.Retention.Mode.locked),
    ("MODE_UNSPECIFIED", Object.Retention.Mode.unspecified),
    ("mode_unspecified", Object.Retention.Mode.unspecified),
    ("CUSTOM_POLICY", Object.Retention.Mode.unknownStringValue("CUSTOM_POLICY")),
    (nil as String?, Object.Retention.Mode.unspecified),
  ])
  func retentionModeConversions(
    modeInput: String?, expectedMode: Object.Retention.Mode
  ) throws {
    let modeJSON = modeInput.map { "\"mode\": \"\($0)\"," } ?? ""
    let json = """
      {
        "retention": {
          \(modeJSON)
          "retainUntilTime": "2028-01-01T00:00:00Z"
        }
      }
      """
    let data = try #require(json.data(using: .utf8))
    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let v1 = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1.toObject()

    #expect(object.retention?.mode == expectedMode)
    #expect(object.retention?.retainUntilTime != nil)
  }

  @Test func programmaticV1ResponseConversion() throws {
    var v1 = ObjectV1Response()
    v1.name = "programmatic-object"
    v1.bucket = "programmatic-bucket"
    v1.etag = "etag-abc"
    v1.contentType = "text/plain"
    v1.metadata = ["env": "test"]

    let object = v1.toObject()
    #expect(object.name == "programmatic-object")
    #expect(object.bucket == "projects/_/buckets/programmatic-bucket")
    #expect(object.etag == "etag-abc")
    #expect(object.contentType == "text/plain")
    #expect(object.metadata == ["env": "test"])
    #expect(object.generation == 0)
    #expect(object.size == 0)
  }

  @Test func bucketFormattingVariants() throws {
    var v1 = ObjectV1Response()
    v1.bucket = "projects/_/buckets/already-prefixed"
    #expect(v1.toObject().bucket == "projects/_/buckets/already-prefixed")
  }
}
