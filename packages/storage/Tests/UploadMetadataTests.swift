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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
import GoogleCloudWkt
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct UploadMetadataTests {
  private func makeClient(registry: MockRegistry) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    return try StorageClient(options, mock: registry)
  }

  @Test func uploadMetadataEncodingAndDecoding() throws {
    let customTime = try GoogleCloudWkt.Timestamp(seconds: 1_700_000_000, nanos: 0)
    let aclEntry = ObjectAccessControl().with {
      $0.entity = "user-test@example.com"
      $0.role = "READER"
    }
    let retention = ObjectRetention().with {
      $0.mode = "Unlocked"
      $0.retainUntilTime = customTime
    }
    let owner = ObjectOwner().with {
      $0.entity = "user-owner@example.com"
    }

    let uploadMetadata = UploadMetadata().with {
      $0.contentType = "text/plain"
      $0.contentEncoding = "gzip"
      $0.contentDisposition = "inline"
      $0.contentLanguage = "en"
      $0.cacheControl = "public, max-age=3600"
      $0.customMetadata = ["env": "test", "team": "cloud"]
      $0.storageClass = "NEARLINE"
      $0.customTime = customTime
      $0.eventBasedHold = true
      $0.temporaryHold = false
      $0.acl = [aclEntry]
      $0.retention = retention
      $0.owner = owner
    }

    let encoder = JSONEncoder()
    let data = try encoder.encode(uploadMetadata)
    let jsonString = String(data: data, encoding: .utf8) ?? ""

    // Verify key "metadata" (and not "customMetadata") is used in JSON output
    #expect(jsonString.contains("\"metadata\":"))
    #expect(!jsonString.contains("\"customMetadata\":"))
    #expect(jsonString.contains("gzip"))
    #expect(jsonString.contains("NEARLINE"))
    #expect(jsonString.contains("user-test@example.com"))

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(UploadMetadata.self, from: data)

    #expect(decoded == uploadMetadata)
    #expect(decoded.contentType == "text/plain")
    #expect(decoded.contentEncoding == "gzip")
    #expect(decoded.contentDisposition == "inline")
    #expect(decoded.contentLanguage == "en")
    #expect(decoded.cacheControl == "public, max-age=3600")
    #expect(decoded.customMetadata == ["env": "test", "team": "cloud"])
    #expect(decoded.storageClass == "NEARLINE")
    #expect(decoded.customTime == customTime)
    #expect(decoded.eventBasedHold == true)
    #expect(decoded.temporaryHold == false)
    #expect(decoded.acl == [aclEntry])
    #expect(decoded.retention == retention)
    #expect(decoded.owner == owner)
  }

  @Test func simpleUploadWithUploadMetadataInUploadOptions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 65, count: 100)  // 'A's
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)&predefinedAcl=publicRead"
    )

    let responseJson = """
      {
        "bucket": "\(bucket)",
        "name": "\(objectName)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "text/plain",
        "contentEncoding": "gzip",
        "storageClass": "STANDARD",
        "metadata": {
          "author": "swift-sdk"
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(responseJson.utf8), headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let uploadMetadata = UploadMetadata().with {
      $0.contentType = "text/plain"
      $0.contentEncoding = "gzip"
      $0.customMetadata = ["author": "swift-sdk"]
    }
    let uploadOptions = UploadOptions().with {
      $0.metadata = uploadMetadata
      $0.predefinedAcl = .publicRead
    }

    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.contentType == "text/plain")
    #expect(object.contentEncoding == "gzip")
    #expect(object.metadata == ["author": "swift-sdk"])

    // Inspect recorded HTTP request to verify metadata payload and predefinedAcl query parameter
    let recordedReq = registry.lastRequest(for: simpleUploadUrl)
    #expect(recordedReq != nil)
    if let body = recordedReq?.httpBody, let bodyString = String(data: body, encoding: .utf8) {
      #expect(bodyString.contains("\"metadata\":{\"author\":\"swift-sdk\"}"))
      #expect(bodyString.contains("Content-Type: text/plain"))
    }
  }

  @Test func resumableUploadWithUploadMetadata() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "resumable-object"
    let data = Data(repeating: 67, count: 10 * 1024 * 1024)  // 10MB -> resumable
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)&predefinedAcl=private"
    )
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=session123")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    let finalObjectJson = """
      {
        "bucket": "\(bucket)",
        "name": "\(objectName)",
        "generation": "2",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "image/png",
        "storageClass": "NEARLINE",
        "metadata": {
          "resolution": "1080p"
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(finalObjectJson.utf8), headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let metadata = UploadMetadata().with {
      $0.contentType = "image/png"
      $0.customMetadata = ["resolution": "1080p"]
      $0.storageClass = "NEARLINE"
    }
    let uploadOptions = UploadOptions().with {
      $0.metadata = metadata
      $0.predefinedAcl = .private
    }

    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.contentType == "image/png")
    #expect(object.storageClass == "NEARLINE")
    #expect(object.metadata == ["resolution": "1080p"])

    // Verify initial POST request contains metadata JSON
    let recordedInitReq = registry.lastRequest(for: initUrl)
    #expect(recordedInitReq != nil)
    if let body = recordedInitReq?.httpBody, let bodyString = String(data: body, encoding: .utf8) {
      #expect(bodyString.contains("\"metadata\":{\"resolution\":\"1080p\"}"))
      #expect(bodyString.contains("\"storageClass\":\"NEARLINE\""))
    }
  }

  @Test func storageObjectMetadataDeserialization() throws {
    let jsonString = """
      {
        "bucket": "my-bucket",
        "name": "image.png",
        "generation": "100",
        "metageneration": "5",
        "size": "2048",
        "contentType": "image/png",
        "contentEncoding": "identity",
        "contentDisposition": "inline",
        "contentLanguage": "en",
        "cacheControl": "private",
        "storageClass": "COLDLINE",
        "customTime": "2026-01-01T00:00:00Z",
        "timeCreated": "2026-01-01T00:00:00Z",
        "updated": "2026-01-01T01:00:00Z",
        "eventBasedHold": true,
        "temporaryHold": false,
        "metadata": {
          "app": "swift-storage",
          "version": "1.0"
        },
        "acl": [
          {
            "entity": "user-test@example.com",
            "role": "OWNER"
          }
        ],
        "retention": {
          "mode": "Unlocked",
          "retainUntilTime": "2027-01-01T00:00:00Z"
        },
        "owner": {
          "entity": "user-owner@example.com",
          "entityId": "owner123"
        }
      }
      """
    guard let data = jsonString.data(using: .utf8) else {
      Issue.record("Failed to convert JSON string to Data")
      return
    }

    let decoder = GoogleCloudWkt._ProtoJSONDecoder()
    let object = try decoder.decode(Object.self, from: data)

    #expect(object.bucket == "my-bucket")
    #expect(object.name == "image.png")
    #expect(object.generation == 100)
    #expect(object.metageneration == 5)
    #expect(object.size == 2048)
    #expect(object.contentType == "image/png")
    #expect(object.contentEncoding == "identity")
    #expect(object.contentDisposition == "inline")
    #expect(object.contentLanguage == "en")
    #expect(object.cacheControl == "private")
    #expect(object.storageClass == "COLDLINE")
    #expect(object.eventBasedHold == true)
    #expect(object.temporaryHold == false)
    #expect(object.metadata == ["app": "swift-storage", "version": "1.0"])
    #expect(object.acl.count == 1)
    #expect(object.acl.first?.entity == "user-test@example.com")
    #expect(object.acl.first?.role == "OWNER")
    #expect(
      object.retention?.mode == .unlocked
        || object.retention?.mode == .unknownStringValue("Unlocked"))
    #expect(object.owner?.entity == "user-owner@example.com")
    #expect(object.owner?.entityId == "owner123")
  }

  @Test func uploadMetadataWithObjectContextsEncodingAndDecoding() throws {
    let createTime = try GoogleCloudWkt.Timestamp(seconds: 1_700_000_000, nanos: 0)
    let updateTime = try GoogleCloudWkt.Timestamp(seconds: 1_700_000_100, nanos: 0)

    let contexts = ObjectContexts(custom: [
      "customer_id": ObjectCustomContextPayload(
        value: "cust-78901", createTime: createTime, updateTime: updateTime),
      "payment_status": "unpaid",
    ])

    let uploadMetadata = UploadMetadata().with {
      $0.contentType = "application/json"
      $0.contexts = contexts
    }

    #expect(uploadMetadata.contexts?.custom["customer_id"]?.value == "cust-78901")
    #expect(uploadMetadata.contexts?.custom["payment_status"]?.value == "unpaid")

    let encoder = JSONEncoder()
    let data = try encoder.encode(uploadMetadata)
    let jsonString = String(data: data, encoding: .utf8) ?? ""

    #expect(jsonString.contains("\"contexts\":"))
    #expect(jsonString.contains("\"custom\":"))
    #expect(jsonString.contains("\"customer_id\":"))
    #expect(jsonString.contains("\"cust-78901\""))
    #expect(jsonString.contains("\"payment_status\":"))
    #expect(jsonString.contains("\"unpaid\""))

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(UploadMetadata.self, from: data)

    #expect(decoded == uploadMetadata)
    #expect(decoded.contexts?.custom["customer_id"]?.value == "cust-78901")
    #expect(decoded.contexts?.custom["customer_id"]?.createTime == createTime)
    #expect(decoded.contexts?.custom["customer_id"]?.updateTime == updateTime)
    #expect(decoded.contexts?.custom["payment_status"]?.value == "unpaid")
  }

  @Test func simpleUploadWithObjectContextsInUploadOptions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "context-object"
    let data = Data(repeating: 65, count: 100)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)"
    )

    let responseJson = """
      {
        "bucket": "\(bucket)",
        "name": "\(objectName)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "text/plain",
        "contexts": {
          "custom": {
            "dept": {
              "value": "engineering"
            },
            "environment": {
              "value": "production"
            }
          }
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(responseJson.utf8), headers: nil),
      for: simpleUploadUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.metadata = UploadMetadata().with {
        $0.contexts = ObjectContexts(customValues: [
          "dept": "engineering", "environment": "production",
        ])
      }
    }

    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.contexts?.custom["dept"]?.value == "engineering")
    #expect(object.contexts?.custom["environment"]?.value == "production")

    let recordedReq = registry.lastRequest(for: simpleUploadUrl)
    #expect(recordedReq != nil)
    if let body = recordedReq?.httpBody, let bodyString = String(data: body, encoding: .utf8) {
      #expect(bodyString.contains("\"contexts\":"))
      #expect(bodyString.contains("\"engineering\""))
      #expect(bodyString.contains("\"production\""))
    }
  }

  @Test func resumableUploadWithObjectContexts() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "resumable-context-object"
    let data = Data(repeating: 68, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)"
    )
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=session456")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    let finalObjectJson = """
      {
        "bucket": "\(bucket)",
        "name": "\(objectName)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contexts": {
          "custom": {
            "batch_id": {
              "value": "2026_Q3"
            }
          }
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(finalObjectJson.utf8), headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.metadata = UploadMetadata().with {
        $0.contexts = ObjectContexts(customValues: ["batch_id": "2026_Q3"])
      }
    }

    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.contexts?.custom["batch_id"]?.value == "2026_Q3")

    let recordedInitReq = registry.lastRequest(for: initUrl)
    #expect(recordedInitReq != nil)
    if let body = recordedInitReq?.httpBody, let bodyString = String(data: body, encoding: .utf8) {
      #expect(
        bodyString.contains("\"contexts\":{\"custom\":{\"batch_id\":{\"value\":\"2026_Q3\"}}}"))
    }
  }
}
