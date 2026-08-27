// Copyright 2026 Google LLC
//
// Licensed under the Apache License, License.0 (the "License");
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
@_spi(GoogleCloudInternal) import GoogleCloudWKT
@testable import GoogleCloudStorage
import Testing

@Suite struct StorageObjectTests {
  @Test func storageObjectDefaultValues() {
    let object = Object()
    #expect(object.bucket == "")
    #expect(object.name == "")
    #expect(object.generation == 0)
    #expect(object.metageneration == 0)
    #expect(object.size == 0)
    #expect(object.contentType == "")
    #expect(object.createTime == nil)
    #expect(object.updateTime == nil)
  }

  @Test func storageObjectWithHelperAllFields() throws {
    let timeCreated = try GoogleCloudWKT.Timestamp(seconds: 12345, nanos: 6789)
    let updated = try GoogleCloudWKT.Timestamp(seconds: 67890, nanos: 1234)

    let object = Object().with {
      $0.bucket = "my-bucket"
      $0.name = "my-object"
      $0.generation = 123
      $0.metageneration = 456
      $0.size = 1024
      $0.contentType = "application/json"
      $0.createTime = timeCreated
      $0.updateTime = updated
    }

    #expect(object.bucket == "my-bucket")
    #expect(object.name == "my-object")
    #expect(object.generation == 123)
    #expect(object.metageneration == 456)
    #expect(object.size == 1024)
    #expect(object.contentType == "application/json")
    #expect(object.createTime == timeCreated)
    #expect(object.updateTime == updated)
  }

  @Test func storageObjectJSONDeserializationStringValues() throws {
    let jsonString = """
      {
        "bucket": "test-bucket",
        "name": "folder/test.json",
        "generation": "1234",
        "metageneration": "1",
        "size": "42",
        "contentType": "application/json",
        "createTime": "1970-01-01T00:00:01.000000002Z",
        "updateTime": "1970-01-01T00:00:01.000000002Z"
      }
      """
    guard let data = jsonString.data(using: .utf8) else {
      Issue.record("Failed to convert JSON string to data")
      return
    }

    let decoder = GoogleCloudWKT._ProtoJSONDecoder()
    let object = try decoder.decode(Object.self, from: data)

    #expect(object.bucket == "test-bucket")
    #expect(object.name == "folder/test.json")
    #expect(object.generation == 1234)
    #expect(object.metageneration == 1)
    #expect(object.size == 42)
    #expect(object.contentType == "application/json")
    #expect(object.createTime != nil)
    #expect(object.updateTime != nil)

    let expectedTime = try GoogleCloudWKT.Timestamp(seconds: 1, nanos: 2)
    #expect(object.createTime == expectedTime)
    #expect(object.updateTime == expectedTime)
  }

  @Test func storageObjectWithContextsDeserialization() throws {
    let jsonString = """
      {
        "bucket": "my-bucket",
        "name": "data.bin",
        "generation": "1",
        "metageneration": "1",
        "size": "1024",
        "contexts": {
          "custom": {
            "classification": {
              "value": "confidential",
              "createTime": "2026-08-01T10:00:00Z",
              "updateTime": "2026-08-01T10:30:00Z"
            }
          }
        }
      }
      """
    guard let data = jsonString.data(using: .utf8) else {
      Issue.record("Failed to convert JSON string to Data")
      return
    }

    let decoder = GoogleCloudWKT._ProtoJSONDecoder()
    let object = try decoder.decode(Object.self, from: data)

    #expect(object.bucket == "my-bucket")
    #expect(object.name == "data.bin")
    #expect(object.contexts?.custom["classification"]?.value == "confidential")
    #expect(object.contexts?.custom["classification"]?.createTime != nil)
    #expect(object.contexts?.custom["classification"]?.updateTime != nil)
  }

  @Test func storageObjectJSONDeserializationV1FieldNames() throws {
    let jsonString = """
      {
        "bucket": "test-bucket",
        "name": "folder/test.json",
        "generation": "1234",
        "metageneration": "1",
        "size": "42",
        "contentType": "application/json",
        "timeCreated": "1970-01-01T00:00:01.000000002Z",
        "updated": "1970-01-01T00:00:01.000000002Z",
        "timeStorageClassUpdated": "1970-01-01T00:00:03.000000000Z",
        "retentionExpirationTime": "1970-01-01T00:00:04.000000000Z",
        "crc32c": "AAAAAA==",
        "md5Hash": "1B2M2Y8AsgTpgAmY7PhCfg=="
      }
      """
    guard let data = jsonString.data(using: .utf8) else {
      Issue.record("Failed to convert JSON string to data")
      return
    }

    let decoder = GoogleCloudWKT._ProtoJSONDecoder()
    let v1Object = try decoder.decode(ObjectV1Response.self, from: data)
    let object = v1Object.toObject()

    #expect(object.bucket == "projects/_/buckets/test-bucket")
    #expect(object.name == "folder/test.json")
    #expect(object.generation == 1234)
    #expect(object.metageneration == 1)
    #expect(object.size == 42)
    #expect(object.contentType == "application/json")
    #expect(object.createTime != nil)
    #expect(object.updateTime != nil)
    #expect(object.updateStorageClassTime != nil)
    #expect(object.retentionExpireTime != nil)
    #expect(object.checksums != nil)

    let expectedTime = try GoogleCloudWKT.Timestamp(seconds: 1, nanos: 2)
    #expect(object.createTime == expectedTime)
    #expect(object.updateTime == expectedTime)
  }
}
