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
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C
@testable import GoogleCloudStorage
import Testing

@Suite struct ResumableUploadTests {
  private func sampleKey() -> (data: Data, keyBase64: String, keyHashBase64: String) {
    let keyData = Data(repeating: 0x42, count: 32)
    let keyBase64 = keyData.base64EncodedString()
    let sha256Digest = SHA256.hash(data: keyData)
    let keyHashBase64 = Data(sha256Digest).base64EncodedString()
    return (keyData, keyBase64, keyHashBase64)
  }

  /// Tests a basic single-chunk resumable upload (> 8MB payload) starting a session and completing upload.
  @Test func resumableUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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
        $0.credentials = try! Credentials(configuration: .anonymous)
        $0.retryPolicy = NeverRetry()
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectError(RequestError.self) {
      _ = try await task.value
    }
    if case .io(let underlying as URLError) = error {
      #expect(underlying.code == .cannotConnectToHost)
    } else {
      Issue.record("Expected RequestError.io(URLError), got \(String(describing: error))")
    }
  }

  /// Tests handling of HTTP error responses (e.g. HTTP 500) during chunk upload in a resumable session.
  @Test func resumableUploadHTTPError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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

  /// Tests resuming an interrupted upload when GCS reports a partial offset (Range header), seeking the source and completing remaining bytes.
  @Test func resumeUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  /// Tests resuming an upload using `x-goog-running-hash` header to seed CRC32C without re-reading bytes 0..<offset locally.
  @Test func testResumeUploadWithXGoogRunningHash() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let fullData = Data(repeating: 42, count: 16)
    let firstPart = Data(repeating: 42, count: 8)

    let firstPartCRC = _CRC32C.compute(firstPart)
    let firstPartBigEndian = firstPartCRC.bigEndian
    var firstPartBytes = [UInt8]()
    withUnsafeBytes(of: firstPartBigEndian) { firstPartBytes = Array($0) }
    let runningHashHeader = "crc32c=" + Data(firstPartBytes).base64EncodedString()

    let fullCRC = _CRC32C.compute(fullData)
    let fullBigEndian = fullCRC.bigEndian
    var fullBytes = [UInt8]()
    withUnsafeBytes(of: fullBigEndian) { fullBytes = Array($0) }
    let expectedFullHashHeader = "crc32c=" + Data(fullBytes).base64EncodedString()

    let source = BytesSource(data: fullData)
    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=running-hash-id")

    let objectJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(fullData.count)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: [
          "Range": "bytes=0-7",
          "x-goog-running-hash": runningHashHeader,
        ]),
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    let object = try await task.value
    #expect(object.name == objectName)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    let putRequest = requests[1]
    let hashHeader = putRequest.value(forHTTPHeaderField: "X-Goog-Hash")
    #expect(hashHeader == expectedFullHashHeader)
  }

  /// Tests error handling when `SeekableUploadSource.seek` fails to seek to the server's reported offset.
  @Test func resumeUploadSourceSeekError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MiB
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
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

  @Test func resumableUploadWithCSEKHeaders() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-csek-resumable"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let sample = sampleKey()
    let csek = try CustomerEncryptionKeyOptions(key: sample.data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=csek-upload-id")

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
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: responseJSON.data(using: .utf8)!,
        headers: nil),
      for: chunkUrl)

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
    #expect(object.customerEncryption?.keySha256 == sample.keyHashBase64)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)

    // Verify start request headers
    let startReq = requests[0]
    #expect(startReq.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(startReq.value(forHTTPHeaderField: "x-goog-encryption-key") == sample.keyBase64)
    #expect(
      startReq.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == sample.keyHashBase64)

    // Verify chunk PUT request headers
    let chunkReq = requests[1]
    #expect(chunkReq.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(chunkReq.value(forHTTPHeaderField: "x-goog-encryption-key") == sample.keyBase64)
    #expect(
      chunkReq.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == sample.keyHashBase64)
  }

  // MARK: - Upload Source Types Unit Tests

  // --- Source Type 1: Fixed Buffers in Memory ---

  /// Tests resumable upload using a fixed buffer in memory (`BytesSource`).
  @Test func resumableUploadFixedBufferMemorySuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "fixed-buffer-object"
    let data = Data(repeating: 0xAB, count: 10 * 1024 * 1024)  // 10MiB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=fixed-buffer-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == Int64(data.count))
  }

  /// Tests resuming an interrupted upload for a fixed buffer in memory (`BytesSource`).
  @Test func resumeUploadFixedBufferMemorySuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "fixed-buffer-resumed"
    let data = Data(repeating: 0xCD, count: 10 * 1024 * 1024)  // 10MiB
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=fixed-buffer-resume-id")

    // GCS reports 5MB uploaded (bytes 0-5242879 received)
    let offset: Int64 = 5 * 1024 * 1024
    let lastByte = offset - 1

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(lastByte)"]),
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    // First is status query
    #expect(requests[0].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    // Second is remaining chunk request starting at 5MB
    #expect(
      requests[1].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(offset)-\(data.count - 1)/\(data.count)")
  }

  // --- Source Type 2: Files from Disk ---

  /// Tests resumable upload reading directly from a local file on disk (`FileSource`).
  @Test func resumableUploadFileFromDiskSuccess() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("test_disk_upload_\(UUID().uuidString).dat")
    let data = Data(repeating: 0xEF, count: 10 * 1024 * 1024)  // 10MiB file
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "file-from-disk-object"
    let source = FileSource(fileURL: fileURL)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=disk-file-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == Int64(data.count))
  }

  /// Tests resuming an interrupted upload from a local file on disk (`FileSource`), seeking within the file.
  @Test func resumeUploadFileFromDiskSuccess() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("test_disk_resume_\(UUID().uuidString).dat")
    let data = Data(repeating: 0x42, count: 10 * 1024 * 1024)  // 10MiB file
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "file-from-disk-resumed"
    let source = FileSource(fileURL: fileURL)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=disk-file-resume-id")
    let resumeOffset: Int64 = 4 * 1024 * 1024  // GCS already received 4MB

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(resumeOffset - 1)"]),
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(
      requests[1].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(resumeOffset)-\(data.count - 1)/\(data.count)")
  }

  // --- Source Type 3: Dynamically Created Data via Computation ---

  /// Tests resumable upload of data generated dynamically on-the-fly via computation with a known total size.
  @Test func resumableUploadDynamicComputationKnownSizeSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "dynamic-computation-known"
    let chunkSize = 4 * 1024 * 1024
    let totalChunks = 3
    let totalSize = Int64(chunkSize * totalChunks)  // 12MB

    let source = DynamicComputationSource(
      chunkSize: chunkSize, totalChunks: totalChunks, totalSize: totalSize)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=dynamic-comp-known-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(totalSize)),
        headers: nil),
      for: chunkUrl)

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
    #expect(object.size == totalSize)
  }

  /// Tests resumable upload of dynamically computed data where total size is unknown (`nil`).
  @Test func resumableUploadDynamicComputationUnknownSizeSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "dynamic-computation-unknown"
    let chunkSize = 4 * 1024 * 1024
    let totalChunks = 2
    let expectedTotalSize: Int64 = Int64(chunkSize * totalChunks)  // 8MB

    let source = DynamicComputationSource(
      chunkSize: chunkSize, totalChunks: totalChunks, totalSize: nil)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=dynamic-comp-unknown-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    // Chunk 1 (intermediate chunk -> 308)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunkSize - 1)"]),
      for: chunkUrl)
    // Chunk 2 (final chunk -> 200 OK)
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(expectedTotalSize)),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let uploadOptions = UploadOptions().with { $0.chunkSize = chunkSize }
    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == expectedTotalSize)

    let requests = registry.recordedRequests()
    #expect(requests.count == 3)
    // Request 0 is start resumable
    // Request 1 is chunk 1 (intermediate, total length *)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes 0-\(chunkSize - 1)/*")
    // Request 2 is chunk 2 (final chunk, specifies final total length)
    #expect(
      requests[2].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(chunkSize)-\(expectedTotalSize - 1)/\(expectedTotalSize)")
  }

  /// Tests resuming an interrupted upload for a seekable computational source.
  @Test func resumeUploadDynamicComputationSeekableSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "dynamic-computation-seekable-resumed"
    let chunkSize = 4 * 1024 * 1024
    let totalChunks = 3
    let totalSize = Int64(chunkSize * totalChunks)  // 12MB

    let source = SeekableComputationSource(chunkSize: chunkSize, totalChunks: totalChunks)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=dynamic-seek-resume-id")
    let resumeOffset: Int64 = Int64(chunkSize)  // 4MB already received

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(resumeOffset - 1)"]),
      for: queryUrl)
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(totalSize)),
        headers: nil),
      for: queryUrl)

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
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == totalSize)
  }

  // --- Source Type 4: Data Received Asynchronously from External Source (e.g. Download) ---

  /// Tests resumable upload of data received asynchronously via `AsyncStream<Data>` with unknown total size (`nil`).
  @Test func resumableUploadAsyncStreamUnknownSizeSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "async-download-stream-unknown"
    let chunk1 = Data(repeating: 0x11, count: 5 * 1024 * 1024)
    let chunk2 = Data(repeating: 0x22, count: 5 * 1024 * 1024)
    let expectedTotalSize = Int64(chunk1.count + chunk2.count)

    let asyncStream = makeAsyncStream(chunks: [chunk1, chunk2])
    let source = StreamSource(sequence: asyncStream)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=async-download-unknown-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(expectedTotalSize)),
        headers: nil),
      for: chunkUrl)

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
    #expect(object.size == expectedTotalSize)
  }

  /// Tests resumable upload of data received asynchronously via `AsyncStream<Data>` with a known total size.
  @Test func resumableUploadAsyncStreamKnownSizeSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "async-download-stream-known"
    let chunk1 = Data(repeating: 0x33, count: 5 * 1024 * 1024)
    let chunk2 = Data(repeating: 0x44, count: 5 * 1024 * 1024)
    let totalSize = Int64(chunk1.count + chunk2.count)  // 10MiB

    let asyncStream = makeAsyncStream(chunks: [chunk1, chunk2])
    let source = StreamSource(sequence: asyncStream, totalSize: totalSize)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=async-download-known-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(totalSize)),
        headers: nil),
      for: chunkUrl)

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
    #expect(object.size == totalSize)
  }

  /// Tests resumable upload of an empty asynchronous stream (0 bytes).
  @Test func resumableUploadAsyncStreamEmptyStreamSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "async-download-empty"

    let asyncStream = makeAsyncStream(chunks: [])
    let source = StreamSource(sequence: asyncStream)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=async-download-empty-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: chunkUrl)

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
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */0")
  }

  /// Tests resumable upload with unknown total size (`totalSize == nil`), where data chunks are sent
  /// with unknown total size (`*`), and the stream finishes with an empty final chunk specifying the final total size (`Content-Range: bytes */TOTAL`).
  @Test func resumableUploadUnknownSizeStreamWithEmptyFinalChunkSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "async-stream-empty-final-chunk"
    let chunk1 = Data(repeating: 0x11, count: 5 * 1024 * 1024)
    let chunk2 = Data(repeating: 0x22, count: 5 * 1024 * 1024)
    let expectedTotalSize = Int64(chunk1.count + chunk2.count)  // 10MB

    let asyncStream = makeAsyncStream(chunks: [chunk1, chunk2, Data()])
    let source = StreamSource(sequence: asyncStream)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=async-stream-empty-final-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    // Chunk 1 (5MB) -> 308
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunk1.count - 1)"]),
      for: chunkUrl)
    // Chunk 2 (5MB) -> 308
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(expectedTotalSize - 1)"]),
      for: chunkUrl)
    // Final empty chunk (0 bytes) specifying final total size -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: Int(expectedTotalSize)),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let uploadOptions = UploadOptions().with { $0.chunkSize = 5 * 1024 * 1024 }
    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == expectedTotalSize)

    let requests = registry.recordedRequests()
    #expect(requests.count >= 2)
    #expect(
      requests.last?.value(forHTTPHeaderField: "Content-Range") == "bytes */\(expectedTotalSize)")
  }

  /// Tests resumable upload of a dynamic computation source where total size is unknown (`nil`), but turns out to be completely empty (0 bytes).
  @Test func resumableUploadDynamicComputationUnknownSizeCompletelyEmptySuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "dynamic-computation-unknown-empty"

    let source = DynamicComputationSource(
      chunkSize: 4 * 1024 * 1024, totalChunks: 0, totalSize: nil)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=dynamic-comp-unknown-empty-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: chunkUrl)

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
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */0")
  }

  /// Tests resuming an upload from an intermediate offset when MD5 checksum was requested (.auto).
  /// Because MD5 is not recoverable from a partial state, MD5 calculation must be skipped,
  /// and no md5 checksum header should be sent in the final chunk upload request.
  @Test func testResumeUploadPartialWithAutoMD5Skipped() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=auto-md5-partial-upload-id")

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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let task = client.resumeUpload(
      source, uploadId: queryUrl.absoluteString, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    let finalChunkReq = requests[1]
    let hashHeader = finalChunkReq.value(forHTTPHeaderField: "x-goog-hash")
    #expect(hashHeader == nil)
  }

  /// Tests resuming an upload from offset 0 when MD5 checksum was requested (.auto).
  /// Because the upload starts from byte 0 (not partially complete), MD5 calculation SHOULD occur and be sent.
  @Test func testResumeUploadFromOffsetZeroWithAutoMD5() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 1 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=zero-offset-md5-upload-id")

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
        headers: [:]),
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
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let task = client.resumeUpload(
      source, uploadId: queryUrl.absoluteString, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    let finalChunkReq = requests[1]
    let hashHeader = finalChunkReq.value(forHTTPHeaderField: "x-goog-hash")
    #expect(hashHeader != nil)
    #expect(hashHeader?.contains("md5=") == true)
  }

  /// Tests that a transient error during a chunk upload is retried by `_RetryLoop`
  /// using `queryUploadStatus` to recover the committed offset before resending.
  @Test func resumableUploadTransientFailureOnChunkRetriesAndRecovers() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "transient-chunk-recovery"
    let data = Data(repeating: 0xAB, count: 16 * 1024 * 1024)  // 16MiB (2 chunks of 8MiB)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=transient-session-id")

    // 1. Session start succeeds
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. First chunk (0..8MB) succeeds -> 308 Range 0-8388607
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-8388607"]),
      for: sessionUrl)

    // 3. Second chunk (8MB..16MB) fails transiently with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 4. Retry loop queries status -> 308 Range 0-8388607
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-8388607"]),
      for: sessionUrl)

    // 5. Second chunk re-attempt succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: sessionUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        $0.retryPolicy = BaseRetryPolicy().withAttemptLimit(3)
        $0.backoffPolicy = try! ExponentialBackoff(
          config: ExponentialBackoffConfig().with {
            $0.initialDelay = .nanoseconds(1_000_000)
            $0.maximumDelay = .nanoseconds(10_000_000)
          }
        )
      }
    }

    let client = try StorageClient(options, testSession: session)
    let uploadOptions = UploadOptions().with {
      $0.chunkSize = 8 * 1024 * 1024
    }
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 5)
    // 0: Start request
    #expect(requests[0].httpMethod == "POST")
    // 1: Chunk 1 (0-8MB)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/16777216")
    // 2: Chunk 2 first attempt (8MB-16MB)
    #expect(
      requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes 8388608-16777215/16777216")
    // 3: Status query after transient failure
    #expect(requests[3].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    // 4: Chunk 2 second attempt (8MB-16MB)
    #expect(
      requests[4].value(forHTTPHeaderField: "Content-Range") == "bytes 8388608-16777215/16777216")
  }

  /// Tests that a transient error during `resumeUpload` status query is retried by `_RetryLoop`.
  @Test func resumeUploadTransientFailureOnStatusQueryRetriesAndSucceeds() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "transient-query-recovery"
    let data = Data(repeating: 0xEE, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=transient-query-id")

    // 1. First status query fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Unavailable".utf8),
        headers: [:]),
      for: queryUrl)

    // 2. Retry loop queries status again -> succeeds with 308 (4MB uploaded)
    let resumeOffset: Int64 = 4 * 1024 * 1024
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(resumeOffset - 1)"]),
      for: queryUrl)

    // 3. Final chunk upload succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        $0.retryPolicy = BaseRetryPolicy().withAttemptLimit(3)
        $0.backoffPolicy = try! ExponentialBackoff(
          config: ExponentialBackoffConfig().with {
            $0.initialDelay = .nanoseconds(1_000_000)
            $0.maximumDelay = .nanoseconds(10_000_000)
          }
        )
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 3)
    #expect(requests[0].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(
      requests[2].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(resumeOffset)-\(data.count - 1)/\(data.count)")
  }

  /// Tests that a transient error when starting a resumable upload session is retried and completes under the same retry loop.
  @Test func resumableUploadTransientFailureOnSessionStartRetriesAndSucceeds() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "transient-start-recovery"
    let data = Data(repeating: 0xCC, count: 8 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=session-after-start-retry")

    // 1. Initial session start fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: startUrl)

    // 2. Retry of session start succeeds -> 200 OK with Location header
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 3. Chunk upload succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: sessionUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        $0.retryPolicy = BaseRetryPolicy().withAttemptLimit(3)
        $0.backoffPolicy = try! ExponentialBackoff(
          config: ExponentialBackoffConfig().with {
            $0.initialDelay = .nanoseconds(1_000_000)
            $0.maximumDelay = .nanoseconds(10_000_000)
          }
        )
      }
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 3)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[1].httpMethod == "POST")
    #expect(requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
  }

  /// Tests that configuring `retryPolicy` on `UploadOptions` overrides client-level retry policy.
  @Test func resumableUploadWithCustomUploadOptionsRetryPolicyOverridesClient() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "retry-policy-override"
    let data = Data(repeating: 0xDD, count: 8 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    // Session start fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    // Client is configured with default retry policy (which retries 503)
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let client = try StorageClient(options, testSession: session)
    // UploadOptions specifies NeverRetry, so it should fail immediately on the 503 without retrying
    let uploadOptions = UploadOptions().with {
      $0.retryPolicy = NeverRetry()
    }
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    let error = await expectError(RequestError.self) {
      try await task.value
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that configuring `retryPolicy` on `StorageClientOptions.upload` overrides default retry policy.
  @Test func resumableUploadWithClientUploadOptionsRetryPolicyOverridesDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "client-upload-retry-override"
    let data = Data(repeating: 0xDD, count: 8 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    // Session start fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    // StorageClientOptions.upload specifies NeverRetry
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
      $0.upload.retryPolicy = NeverRetry()
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName)

    let error = await expectError(RequestError.self) {
      try await task.value
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that a multi-chunk resumable upload emits exactly one status event per stage without duplicate completion events (#2).
  @Test func resumableUploadStatusStreamHasNoDuplicateCompletionStatus() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-no-dup-status"
    let chunkSize = 8 * 1024 * 1024
    let fileSize = 10 * 1024 * 1024  // 10MB -> 8MB chunk 1 + 2MB chunk 2
    let data = Data(repeating: 0xAA, count: fileSize)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=no-dup-status-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunkSize - 1)"]),
      for: chunkUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: fileSize),
        headers: nil),
      for: chunkUrl)

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

    var statuses: [UploadStatus] = []
    for await status in task.makeStatusStream() {
      statuses.append(status)
    }

    let object = try await task.value
    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(statuses.count == 3)
    #expect(statuses.map(\.bytesUploaded) == [0, Int64(chunkSize), Int64(fileSize)])
    #expect(statuses.map(\.totalBytes) == [Int64(fileSize), Int64(fileSize), Int64(fileSize)])
    #expect(statuses.allSatisfy { $0.uploadId == chunkUrl.absoluteString })
  }

  /// Tests that a single-chunk resumable upload emits initial and final status events without duplicates (#2).
  @Test func resumableUploadSingleChunkStatusStreamHasNoDuplicateCompletionStatus() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-single-chunk-resumable"
    let fileSize = 10 * 1024 * 1024
    let data = Data(repeating: 0xBB, count: fileSize)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=single-chunk-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: fileSize),
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let uploadOptions = UploadOptions().with {
      $0.chunkSize = 16 * 1024 * 1024
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    var statuses: [UploadStatus] = []
    for await status in task.makeStatusStream() {
      statuses.append(status)
    }

    let object = try await task.value
    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(statuses.count == 2)
    #expect(statuses.map(\.bytesUploaded) == [0, Int64(fileSize)])
    #expect(statuses.map(\.totalBytes) == [Int64(fileSize), Int64(fileSize)])
    #expect(statuses.allSatisfy { $0.uploadId == chunkUrl.absoluteString })
  }

  /// Tests that `resumeUpload` emits an initial status event with the server's committed byte offset upon querying status (#3).
  @Test func resumeUploadStatusStreamEmitsInitialCommittedBytes() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resume-initial-status"
    let fileSize = 10 * 1024 * 1024
    let committedBytes = 2 * 1024 * 1024  // 2MB already uploaded
    let data = Data(repeating: 0xCC, count: fileSize)
    let source = BytesSource(data: data)

    let queryUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=resume-initial-status-id")

    // Status query returns 308 with 2MB already uploaded
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(committedBytes - 1)"]),
      for: queryUrl)
    // Upload of remaining 8MB completes with 200
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: fileSize),
        headers: nil),
      for: queryUrl)

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
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    var statuses: [UploadStatus] = []
    for await status in task.makeStatusStream() {
      statuses.append(status)
    }

    let object = try await task.value
    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(statuses.count == 2)
    #expect(statuses.first?.bytesUploaded == Int64(committedBytes))
    #expect(statuses.map(\.bytesUploaded) == [Int64(committedBytes), Int64(fileSize)])
    #expect(statuses.map(\.totalBytes) == [Int64(fileSize), Int64(fileSize)])
    #expect(statuses.allSatisfy { $0.uploadId == queryUrl.absoluteString })
  }

  /// Tests that `resumeUpload` across multiple chunks emits initial committed bytes and each chunk progress without duplicates (#2 & #3).
  @Test func resumeUploadMultiChunkStatusStreamEmitsInitialCommittedBytes() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resume-multi-chunk-status"
    let chunkSize = 2 * 1024 * 1024  // 2MB chunks
    let fileSize = 10 * 1024 * 1024  // 10MB total
    let initialCommitted = 2 * 1024 * 1024  // 2MB already on server
    let data = Data(repeating: 0xDD, count: fileSize)
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=resume-multi-chunk-id")

    // Status query returns 308 (0-2MB uploaded)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(initialCommitted - 1)"]),
      for: queryUrl)
    // Chunk 2: 2MB..4MB (308, Range: 0-4MB-1)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(2 * chunkSize - 1)"]),
      for: queryUrl)
    // Chunk 3: 4MB..6MB (308, Range: 0-6MB-1)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(3 * chunkSize - 1)"]),
      for: queryUrl)
    // Chunk 4: 6MB..8MB (308, Range: 0-8MB-1)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(4 * chunkSize - 1)"]),
      for: queryUrl)
    // Chunk 5: 8MB..10MB (200, Done)
    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: fileSize),
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }

    let uploadOptions = UploadOptions().with {
      $0.chunkSize = chunkSize
    }

    let client = try StorageClient(options, testSession: session)
    let task = client.resumeUpload(
      source, uploadId: queryUrl.absoluteString, options: uploadOptions)

    var statuses: [UploadStatus] = []
    for await status in task.makeStatusStream() {
      statuses.append(status)
    }

    let object = try await task.value
    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
    #expect(statuses.count == 5)
    #expect(
      statuses.map(\.bytesUploaded) == [
        Int64(initialCommitted),
        Int64(2 * chunkSize),
        Int64(3 * chunkSize),
        Int64(4 * chunkSize),
        Int64(fileSize),
      ])
    #expect(statuses.map(\.totalBytes) == Array(repeating: Int64(fileSize), count: 5))
    #expect(statuses.allSatisfy { $0.uploadId == queryUrl.absoluteString })
  }
}

// MARK: - Test Helper Sources

/// A non-seekable computational upload source generating deterministic bytes on-demand.
private struct DynamicComputationSource: UploadSource {
  let chunkSize: Int
  let totalChunks: Int
  let totalSize: Int64?
  private var currentChunk: Int = 0

  init(chunkSize: Int, totalChunks: Int, totalSize: Int64?) {
    self.chunkSize = chunkSize
    self.totalChunks = totalChunks
    self.totalSize = totalSize
  }

  mutating func read(maxBytes: Int) async throws -> Data? {
    guard currentChunk < totalChunks else { return nil }
    let count = min(maxBytes, chunkSize)
    let byteVal = UInt8((currentChunk + 1) % 256)
    currentChunk += 1
    return Data(repeating: byteVal, count: count)
  }
}

/// A seekable computational upload source that can re-initialize its generator to any offset.
private struct SeekableComputationSource: SeekableUploadSource {
  let chunkSize: Int
  let totalChunks: Int
  let totalSize: Int64?
  private var currentOffset: Int64 = 0

  init(chunkSize: Int, totalChunks: Int) {
    self.chunkSize = chunkSize
    self.totalChunks = totalChunks
    self.totalSize = Int64(chunkSize * totalChunks)
  }

  mutating func read(maxBytes: Int) async throws -> Data? {
    guard let totalSize = totalSize, currentOffset < totalSize else { return nil }
    let bytesToRead = min(Int64(maxBytes), totalSize - currentOffset)
    guard bytesToRead > 0 else { return nil }
    let chunkIndex = Int(currentOffset / Int64(chunkSize))
    let byteVal = UInt8((chunkIndex + 1) % 256)
    currentOffset += bytesToRead
    return Data(repeating: byteVal, count: Int(bytesToRead))
  }

  mutating func seek(to offset: Int64) async throws {
    guard offset >= 0, let total = totalSize, offset <= total else {
      throw UploadError.localSourceTooSmall(localSize: totalSize ?? 0, gcsOffset: offset)
    }
    self.currentOffset = offset
  }
}

/// Helper function to create an `AsyncStream<Data>` with asynchronous yielding.
private func makeAsyncStream(chunks: [Data], delayNanoseconds: UInt64 = 1_000_000) -> AsyncStream<
  Data
> {
  return AsyncStream { continuation in
    Task {
      for chunk in chunks {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        continuation.yield(chunk)
      }
      continuation.finish()
    }
  }
}
