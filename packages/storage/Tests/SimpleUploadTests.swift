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

import Crypto
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudAuth
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct SimpleUploadTests {
  private func sampleKey() -> (data: Data, keyBase64: String, keyHashBase64: String) {
    let keyData = Data(repeating: 0x42, count: 32)
    let keyBase64 = keyData.base64EncodedString()
    let sha256Digest = SHA256.hash(data: keyData)
    let keyHashBase64 = Data(sha256Digest).base64EncodedString()
    return (keyData, keyBase64, keyHashBase64)
  }

  /// Tests a successful simple (single-part) upload for payloads smaller than the 8MB resumable threshold.
  @Test func simpleUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: simpleUploadUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests error propagation when the underlying `UploadSource` fails to read source data during a simple upload.
  @Test func simpleUploadSourceReadError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, readError: DummyError())

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    await expectError(DummyError.self) {
      try await task.value
    }
  }

  /// Tests error propagation when a transport/network error occurs during a simple upload.
  @Test func simpleUploadNetworkError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .failure(URLError(.cannotConnectToHost)),
      for: simpleUploadUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        $0.retryPolicy = NeverRetry()
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectError(RequestError.self) {
      try await task.value
    }
    if case .io(let underlying as URLError) = error {
      #expect(underlying.code == .cannotConnectToHost)
    } else {
      Issue.record("Expected RequestError.io(URLError), got \(String(describing: error))")
    }
  }

  /// Tests handling of HTTP error responses (e.g., HTTP 500) during a simple upload.
  @Test func simpleUploadHTTPError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 500, data: Data("Internal Server Error".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectUploadError {
      try await task.value
    }
    if case .unexpectedServerResponse(let statusCode, let message) = error {
      #expect(statusCode == 500)
      #expect(message == "Internal Server Error")
    } else {
      Issue.record("Expected .unexpectedServerResponse, got \(String(describing: error))")
    }
  }

  /// Tests handling of malformed/invalid JSON returned by GCS on a simple upload.
  @Test func simpleUploadInvalidJSONError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: Data("invalid json content".utf8),
        headers: nil),
      for: simpleUploadUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectError(DecodingError.self) {
      try await task.value
    }
    #expect(error != nil)
  }

  /// Tests error handling when `UploadSource.read` unexpectedly returns `nil` before payload bytes are read.
  @Test func simpleUploadSourceReturnsNil() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let source = MockUploadSource(data: Data(), totalSize: 1024)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectUploadError {
      try await task.value
    }
    if case .internalError(let message) = error {
      #expect(message == "Failed to read data from source")
    }
  }

  @Test func simpleUploadWithCSEKHeaders() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-csek-object"
    let data = Data(repeating: 1, count: 1024)
    let source = BytesSource(data: data)

    let sample = sampleKey()
    let csek = try CustomerEncryptionKeyOptions(key: sample.data)

    let simpleUploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    let responseJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "customerEncryption": {
          "encryptionAlgorithm": "AES256",
          "keySha256": "\(sample.keyHashBase64)"
        }
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: responseJSON.data(using: .utf8)!,
        headers: nil),
      for: simpleUploadUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let uploadOptions = UploadOptions().with { $0.customerEncryptionKey = csek }
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.customerEncryption?.encryptionAlgorithm == "AES256")
    #expect(object.customerEncryption?.keySha256 == sample.keyHashBase64)

    let requests = registry.recordedRequests()
    #expect(!requests.isEmpty)
    let uploadReq = requests.first {
      $0.url?.path.contains("/upload/storage/v1/b/\(bucket)/o") == true
    }
    #expect(uploadReq != nil)
    #expect(uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-key") == sample.keyBase64)
    #expect(
      uploadReq?.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == sample.keyHashBase64)
  }
}
