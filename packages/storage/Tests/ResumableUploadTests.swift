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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct ResumableUploadTests {
  /// Tests a basic single-chunk resumable upload (> 8MB payload) starting a session and completing upload.
  @Test func resumableUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let objectJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests error propagation when `UploadSource.read` fails during a resumable chunk upload.
  @Test func resumableUploadSourceReadError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, readError: DummyError())

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    await #expect(throws: DummyError.self) {
      _ = try await task.value
    }
  }

  /// Tests error propagation when network connection fails during resumable session initialization.
  @Test func resumableUploadNetworkError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    registry.register(
      response: .failure(URLError(.cannotConnectToHost)),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    await #expect(throws: URLError.self) {
      _ = try await task.value
    }
  }

  /// Tests handling of HTTP error responses (e.g. HTTP 500) during chunk upload in a resumable session.
  @Test func resumableUploadHTTPError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 500, data: Data("Internal Server Error".utf8),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
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

  /// Tests resuming an interrupted upload when GCS reports a partial offset (Range header), seeking the source and completing remaining bytes.
  @Test func resumeUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let objectJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-4999"]),
      for: queryUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests error handling when `SeekableUploadSource.seek` fails to seek to the server's reported offset.
  @Test func resumeUploadSourceSeekError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, seekError: DummyError())

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-4999"]),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    await #expect(throws: DummyError.self) {
      _ = try await task.value
    }
  }

  /// Tests a multi-chunk resumable upload (20MB payload) streaming progress updates and uploading across multiple intermediate 308 Range acknowledgments.
  @Test func multiChunkResumableUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let chunkSize = 8 * 1024 * 1024
    let end1 = chunkSize - 1
    let end2 = 2 * chunkSize - 1
    let data = Data(repeating: 1, count: 20 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=multi-chunk-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(end1)"]),
      for: chunkUrl)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(end2)"]),
      for: chunkUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    var statuses: [UploadStatus] = []
    for await status in task.makeStatusStream() {
      statuses.append(status)
    }

    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(statuses.count >= 3)
    if let firstStatus = statuses.first, let lastStatus = statuses.last {
      #expect(firstStatus.bytesUploaded == 0)
      #expect(lastStatus.bytesUploaded == Int64(data.count))
    }
  }

  /// Tests resuming an upload session that GCS has already fully completed, returning HTTP 200 and object metadata directly.
  @Test func resumeCompletedOnServer() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=already-done-id")

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests resuming an upload session where GCS returns HTTP 308 without a Range header (0 bytes received), restarting upload from byte 0.
  @Test func resumeZeroBytesOnServer() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=zero-bytes-id")

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: nil),
      for: queryUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests resuming an invalid or expired upload session ID, receiving HTTP 404 from GCS.
  @Test func resumeSessionExpired() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=expired-id")

    registry.register(
      response: .success(
        statusCode: 404, data: Data("Upload session expired".utf8),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    let error = await expectUploadError {
      try await task.value
    }
    if case .unexpectedServerResponse(let statusCode, let message) = error {
      #expect(statusCode == 404)
      #expect(message == "Upload session expired")
    } else {
      Issue.record("Expected .unexpectedServerResponse, got \(error)")
    }
  }

  /// Tests session initialization failure when GCS returns HTTP 200 but lacks the required Location header.
  @Test func resumableMissingLocationHeader() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: nil),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectUploadError {
      try await task.value
    }
    if case .unexpectedServerResponse(let statusCode, let message) = error {
      #expect(statusCode == 200)
      #expect(message == "")
    } else {
      Issue.record("Expected .unexpectedServerResponse, got \(String(describing: error))")
    }
  }

  /// Tests resuming an upload session that was cancelled on GCS, receiving HTTP 499 from GCS.
  @Test func resumeCancelledOnServer() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=cancelled-id")

    registry.register(
      response: .success(
        statusCode: 499, data: Data("Client Closed Request".utf8),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    let error = await expectUploadError {
      try await task.value
    }
    if case .unexpectedServerResponse(let statusCode, let message) = error {
      #expect(statusCode == 499)
      #expect(message == "Client Closed Request")
    } else {
      Issue.record("Expected .unexpectedServerResponse, got \(String(describing: error))")
    }
  }

  /// Tests resuming an upload where GCS reports an offset larger than the local source size, throwing UploadError.localSourceTooSmall.
  @Test func resumeLocalSourceTooSmall() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 100)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=truncated-id")

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-4999"]),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    let error = await expectUploadError {
      try await task.value
    }
    if case .localSourceTooSmall(let localSize, let gcsOffset) = error {
      #expect(localSize == 100)
      #expect(gcsOffset == 5000)
    } else {
      Issue.record("Expected .localSourceTooSmall, got \(String(describing: error))")
    }
  }
}
