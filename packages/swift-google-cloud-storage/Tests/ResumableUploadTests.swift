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
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct ResumableUploadTests {
  private func sampleKey() -> (data: Data, keyBase64: String, keyHashBase64: String) {
    let keyData = Data(repeating: 0x42, count: 32)
    let keyBase64 = keyData.base64EncodedString()
    let sha256Digest = SHA256.hash(data: keyData)
    let keyHashBase64 = Data(sha256Digest).base64EncodedString()
    return (keyData, keyBase64, keyHashBase64)
  }

  private func makeClient(
    registry: MockRegistry,
    clientRetryPolicy: (any RetryPolicy)? = nil,
    uploadResumePolicy: (any ResumePolicy<UploadDetails>)? = nil,
    uploadThreshold: Int? = nil
  ) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        if let clientRetryPolicy {
          $0.retryPolicy = clientRetryPolicy
        }
      }
      if let uploadResumePolicy {
        $0.upload.resumePolicy = uploadResumePolicy
      }
      if let uploadThreshold {
        $0.upload.resumableUploadThreshold = uploadThreshold
      }
    }
    return try StorageClient(options, mock: registry)
  }

  /// Tests a basic single-chunk resumable upload (> 8MB payload) starting a session and completing upload.
  @Test func resumableUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-upload-id-123")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: Data("{\"name\":\"\(objectName)\"}".utf8),
        headers: ["Content-Type": "application/json"]),
      for: chunkUrl)

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
  }

  /// Tests error propagation when network failure (URLError) occurs while initiating a resumable upload session.
  @Test func resumableUploadNetworkFailure() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    registry.register(
      response: .failure(URLError(.cannotConnectToHost)),
      for: startUrl)

    let client = try makeClient(
      registry: registry, uploadResumePolicy: NeverResume<UploadDetails>())

    let error = await expectError(RequestError.self) {
      _ = try await client.upload(source, to: bucket, as: objectName)
    }
    if case .io(let underlying as URLError) = error {
      #expect(underlying.code == URLError.cannotConnectToHost)
    } else {
      Issue.record("Expected RequestError.io(URLError), got \(String(describing: error))")
    }
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

    let client = try makeClient(registry: registry)

    await #expect(throws: DummyError.self) {
      _ = try await client.upload(source, to: bucket, as: objectName)
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

    let client = try makeClient(registry: registry, uploadResumePolicy: NeverResume())

    let error = await expectError(RequestError.self) {
      _ = try await client.upload(source, to: bucket, as: objectName)
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

    let client = try makeClient(registry: registry)

    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    if case .http(let details) = error {
      #expect(details.http_status_code == 500)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)
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

    let client = try makeClient(registry: registry)

    await #expect(throws: DummyError.self) {
      _ = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)
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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)

    let error = await expectError(RequestError.self) {
      try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    }
    if case .http(let details) = error {
      #expect(details.http_status_code == 404)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
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

    let client = try makeClient(registry: registry)

    let error = await expectUploadError {
      try await client.upload(source, to: bucket, as: objectName)
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

    let client = try makeClient(registry: registry)

    let error = await expectError(RequestError.self) {
      try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    }
    if case .http(let details) = error {
      #expect(details.http_status_code == 499)
    } else {
      Issue.record("Expected .http RequestError, got \(String(describing: error))")
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

    let client = try makeClient(registry: registry)

    let error = await expectUploadError {
      try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)
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

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with { $0.customerEncryptionKey = csek }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")

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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")

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
    let totalSize = UInt64(chunkSize * totalChunks)  // 12MB

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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))
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

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with { $0.chunkSize = chunkSize }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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
    let totalSize = UInt64(chunkSize * totalChunks)  // 12MB

    let source = SeekableComputationSource(chunkSize: chunkSize, totalChunks: totalChunks)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=dynamic-seek-resume-id")
    let resumeOffset: UInt64 = UInt64(chunkSize)  // 4MB already received

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

    let client = try makeClient(registry: registry)
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))
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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == expectedTotalSize)
  }

  /// Tests resumable upload of data received asynchronously via `AsyncStream<Data>` with a known total size.
  @Test func resumableUploadAsyncStreamKnownSizeSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "async-download-stream-known"
    let chunk1 = Data(repeating: 0x33, count: 5 * 1024 * 1024)
    let chunk2 = Data(repeating: 0x44, count: 5 * 1024 * 1024)
    let totalSize = UInt64(chunk1.count + chunk2.count)  // 10MiB

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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))
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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with { $0.chunkSize = 5 * 1024 * 1024 }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let object = try await client.resumeUpload(
      source, uploadId: queryUrl.absoluteString, options: uploadOptions)

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

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let object = try await client.resumeUpload(
      source, uploadId: queryUrl.absoluteString, options: uploadOptions)

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

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let uploadOptions = UploadOptions().with {
      $0.chunkSize = 8 * 1024 * 1024
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

  /// Tests that when a chunk fails with 503 and the status query indicates partial data was committed by GCS,
  /// the upload automatically seeks and resumes from the latest committed byte.
  @Test func resumableUploadPartialChunkCommittedOn503ResumesFromLatestByte() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "partial-chunk-recovery"
    let chunkSize = 8 * 1024 * 1024  // 8MiB
    let totalSize = 16 * 1024 * 1024  // 16MiB (2 chunks)
    let partialCommitted = 12 * 1024 * 1024  // 12MiB (8MiB from chunk 1 + 4MiB from chunk 2)
    let data = Data((0..<totalSize).map { UInt8($0 % 251) })
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=partial-commit-session-id")

    // 1. Session start succeeds -> 200 OK with Location
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. First chunk (0..8MB) succeeds -> 308 Range 0-8388607
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunkSize - 1)"]),
      for: sessionUrl)

    // 3. Second chunk (8MB..16MB) fails transiently with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 4. Status query returns 308 showing 12MB committed (partial 4MB of chunk 2 was received by GCS before failure)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(partialCommitted - 1)"]),
      for: sessionUrl)

    // 5. Resumed upload from latest byte (12MB..16MB) succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: totalSize),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let uploadOptions = UploadOptions().with {
      $0.chunkSize = chunkSize
    }
    let object = try await client.upload(
      source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))

    let requests = registry.recordedRequests()
    #expect(requests.count == 5)
    // 0: Start request
    #expect(requests[0].httpMethod == "POST")
    // 1: Chunk 1 (0-8MB)
    #expect(
      requests[1].value(forHTTPHeaderField: "Content-Range")
        == "bytes 0-\(chunkSize - 1)/\(totalSize)")
    // 2: Chunk 2 first attempt (8MB-16MB) - fails with 503
    #expect(
      requests[2].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(chunkSize)-\(totalSize - 1)/\(totalSize)")
    // 3: Status query after transient failure
    #expect(requests[3].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    // 4: Resumed chunk starting from latest committed byte (12MB-16MB)
    #expect(
      requests[4].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(partialCommitted)-\(totalSize - 1)/\(totalSize)")
    // Verify exact data payload sent in the resumed chunk
    #expect(requests[4].httpBody == data.subdata(in: partialCommitted..<totalSize))
  }

  /// Tests that when the first chunk upload fails with 503 and partial data was committed by GCS,
  /// the retry loop seeks the source and resumes from the latest committed byte.
  @Test func resumableUploadPartialFirstChunkCommittedOn503ResumesFromLatestByte() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "partial-first-chunk-recovery"
    let chunkSize = 8 * 1024 * 1024  // 8MiB
    let totalSize = 10 * 1024 * 1024  // 10MiB
    let partialCommitted = 3 * 1024 * 1024  // 3MiB committed during first chunk before 503
    let data = Data((0..<totalSize).map { UInt8($0 % 199) })
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=partial-first-chunk-session-id")

    // 1. Session start succeeds
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. First chunk (0..8MB) fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 3. Status query returns 308 with 3MB committed
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(partialCommitted - 1)"]),
      for: sessionUrl)

    // 4. Chunk 2 sends remaining from 3MB..10MB (7MB) and succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: totalSize),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let uploadOptions = UploadOptions().with {
      $0.chunkSize = chunkSize
    }
    let object = try await client.upload(
      source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))

    let requests = registry.recordedRequests()
    #expect(requests.count == 4)
    #expect(requests[0].httpMethod == "POST")
    #expect(
      requests[1].value(forHTTPHeaderField: "Content-Range")
        == "bytes 0-\(chunkSize - 1)/\(totalSize)")
    #expect(requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(
      requests[3].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(partialCommitted)-\(totalSize - 1)/\(totalSize)")
    #expect(requests[3].httpBody == data.subdata(in: partialCommitted..<totalSize))
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

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let object = try await client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
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

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(3)
    )
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 3)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[1].httpMethod == "POST")
    #expect(requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
  }

  /// Tests that multiple 503 errors occurring across different chunks during a multi-chunk resumable upload
  /// are each retried and recovered by `_RetryLoop`.
  @Test func resumableUploadMultiple503ErrorsAcrossChunksRetriesAndRecovers() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "multi-503-chunk-recovery"
    let chunkSize = 8 * 1024 * 1024
    let totalSize = 24 * 1024 * 1024  // 24MiB (3 chunks of 8MiB)
    let data = Data(repeating: 0x77, count: totalSize)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=multi-503-session-id")

    // 1. Session start succeeds -> 200 OK with Location
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. Chunk 1 (0..8MB) succeeds -> 308 Range 0-8MB
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunkSize - 1)"]),
      for: sessionUrl)

    // 3. Chunk 2 (8MB..16MB) attempt 1 fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 4. Status query for Chunk 2 recovery -> 308 Range 0-8MB
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(chunkSize - 1)"]),
      for: sessionUrl)

    // 5. Chunk 2 (8MB..16MB) attempt 2 succeeds -> 308 Range 0-16MB
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(2 * chunkSize - 1)"]),
      for: sessionUrl)

    // 6. Chunk 3 (16MB..24MB) attempt 1 fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 7. Status query for Chunk 3 recovery -> 308 Range 0-16MB
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-\(2 * chunkSize - 1)"]),
      for: sessionUrl)

    // 8. Chunk 3 (16MB..24MB) attempt 2 succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: totalSize),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(5)
    )
    let uploadOptions = UploadOptions().with {
      $0.chunkSize = chunkSize
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(totalSize))

    let requests = registry.recordedRequests()
    #expect(requests.count == 8)
    // 0: Start request
    #expect(requests[0].httpMethod == "POST")
    // 1: Chunk 1 (0-8MB)
    #expect(
      requests[1].value(forHTTPHeaderField: "Content-Range")
        == "bytes 0-\(chunkSize - 1)/\(totalSize)")
    // 2: Chunk 2 first attempt (8MB-16MB) - fails with 503
    #expect(
      requests[2].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(chunkSize)-\(2 * chunkSize - 1)/\(totalSize)")
    // 3: Status query after Chunk 2 transient failure
    #expect(requests[3].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    // 4: Chunk 2 second attempt (8MB-16MB) - succeeds
    #expect(
      requests[4].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(chunkSize)-\(2 * chunkSize - 1)/\(totalSize)")
    // 5: Chunk 3 first attempt (16MB-24MB) - fails with 503
    #expect(
      requests[5].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(2 * chunkSize)-\(totalSize - 1)/\(totalSize)")
    // 6: Status query after Chunk 3 transient failure
    #expect(requests[6].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    // 7: Chunk 3 second attempt (16MB-24MB) - succeeds
    #expect(
      requests[7].value(forHTTPHeaderField: "Content-Range")
        == "bytes \(2 * chunkSize)-\(totalSize - 1)/\(totalSize)")
  }

  /// Tests that consecutive 503 errors on the same chunk upload are retried with backoff until succeeding.
  @Test func resumableUploadConsecutive503ErrorsOnChunkRetriesAndRecovers() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "consecutive-503-recovery"
    let data = Data(repeating: 0x88, count: 8 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=consecutive-session-id")

    // 1. Session start succeeds
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. Chunk attempt 1 fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable 1".utf8),
        headers: [:]),
      for: sessionUrl)

    // 3. Status query 1 -> 308 (0 bytes committed)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: [:]),
      for: sessionUrl)

    // 4. Chunk attempt 2 fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Service Unavailable 2".utf8),
        headers: [:]),
      for: sessionUrl)

    // 5. Status query 2 -> 308 (0 bytes committed)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: [:]),
      for: sessionUrl)

    // 6. Chunk attempt 3 succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(4)
    )
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 6)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
    #expect(requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(requests[3].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
    #expect(requests[4].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(requests[5].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
  }

  /// Tests that a 503 error during status query recovery after a chunk 503 is also retried and succeeds.
  @Test func resumableUpload503ErrorDuringStatusQueryRecovery() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "status-query-503-recovery"
    let data = Data(repeating: 0x99, count: 8 * 1024 * 1024)
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?upload_id=status-query-503-session-id")

    // 1. Session start succeeds
    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: startUrl)

    // 2. Chunk attempt fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Chunk Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 3. Status query attempt 1 also fails with 503
    registry.register(
      response: .success(
        statusCode: 503, data: Data("Query Service Unavailable".utf8),
        headers: [:]),
      for: sessionUrl)

    // 4. Status query attempt 2 succeeds -> 308 (0 bytes committed)
    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: [:]),
      for: sessionUrl)

    // 5. Chunk retry attempt succeeds -> 200 OK
    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: bucket, size: data.count),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(
      registry: registry,
      clientRetryPolicy: BaseRetryPolicy().withAttemptLimit(4)
    )
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 5)
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
    #expect(requests[2].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(requests[3].value(forHTTPHeaderField: "Content-Range") == "bytes */*")
    #expect(requests[4].value(forHTTPHeaderField: "Content-Range") == "bytes 0-8388607/8388608")
  }

  /// Tests that configuring `resumePolicy` on `UploadOptions` overrides client-level retry policy.
  @Test func resumableUploadWithCustomUploadOptionsResumePolicyOverridesClient() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "resume-policy-override"
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

    let client = try makeClient(registry: registry)
    // UploadOptions specifies NeverResume, so it should fail immediately on the 503 without retrying
    let uploadOptions = UploadOptions().with {
      $0.resumePolicy = NeverResume()
    }
    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that configuring `resumePolicy` on `StorageClientOptions.upload` overrides default retry policy.
  @Test func resumableUploadWithClientUploadOptionsResumePolicyOverridesDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "client-upload-resume-override"
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

    let client = try makeClient(
      registry: registry, uploadResumePolicy: NeverResume<UploadDetails>())
    let error = await expectError(RequestError.self) {
      try await client.upload(source, to: bucket, as: objectName)
    }
    #expect(error != nil)
    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  /// Tests that configuring a lower `resumableUploadThreshold` on `UploadOptions` causes a payload < 8MB to use resumable upload.
  @Test func resumableUploadWithCustomThresholdBelowDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-custom-threshold"
    let data = Data(repeating: 0xBC, count: 1 * 1024 * 1024)  // 1MB (< 8MB default threshold)
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=custom-thresh-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

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
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 512 * 1024  // 512KB threshold
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.url?.absoluteString == initUrl.absoluteString)
    #expect(requests.last?.url?.absoluteString == sessionUrl.absoluteString)
  }

  /// Tests that configuring `resumableUploadThreshold = 0` causes even small payloads to use resumable upload.
  @Test func resumableUploadWithZeroThreshold() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-zero-threshold"
    let data = Data(repeating: 0xCD, count: 100)
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=zero-thresh-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

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
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 0
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.url?.absoluteString == initUrl.absoluteString)
    #expect(requests.last?.url?.absoluteString == sessionUrl.absoluteString)
  }

  /// Tests that configuring `resumableUploadThreshold` on `StorageClientOptions.upload` (client level) causes a payload < 8MB to use resumable upload without specifying request options.
  @Test func resumableUploadWithClientUploadOptionsThresholdBelowDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-client-threshold"
    let data = Data(repeating: 0xDE, count: 1 * 1024 * 1024)  // 1MB (< 8MB default threshold)
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=client-thresh-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

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
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry, uploadThreshold: 512 * 1024)
    let object = try await client.upload(source, to: bucket, as: objectName)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.url?.absoluteString == initUrl.absoluteString)
    #expect(requests.last?.url?.absoluteString == sessionUrl.absoluteString)
  }

  /// Tests that provided `UploadOptions.resumableUploadThreshold` overrides client-level threshold to trigger resumable upload.
  @Test func resumableUploadWithProvidedOptionsOverridingClientUploadOptions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-override-client-threshold"
    let data = Data(repeating: 0xEF, count: 2 * 1024 * 1024)  // 2MB
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=override-client-thresh-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

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
        statusCode: 200, data: Data(objectJSON.utf8),
        headers: nil),
      for: sessionUrl)

    // Client has high threshold (16MB), but call-level options sets 1MB -> resumable upload is chosen
    let client = try makeClient(registry: registry, uploadThreshold: 16 * 1024 * 1024)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 1 * 1024 * 1024
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.url?.absoluteString == initUrl.absoluteString)
    #expect(requests.last?.url?.absoluteString == sessionUrl.absoluteString)
  }

  /// Tests resumable upload of 0-byte Data payload using BytesSource when threshold is 0.
  @Test func resumableUploadZeroByteBytesSourceSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-empty-bytes"
    let data = Data()
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=zero-bytes-source-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 0
    }
    let object = try await client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */0")
    #expect(requests[1].value(forHTTPHeaderField: "x-goog-hash") == "crc32c=AAAAAA==")
  }

  /// Tests resumable upload of 0-byte Data payload with preconditions when threshold is 0.
  @Test func resumableUploadZeroByteDataWithPreconditions() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-empty-preconditions"
    let data = Data()

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)&ifGenerationMatch=0"
    )
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=zero-data-precond-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 0
      $0.preconditions = StoragePreconditions().with {
        $0.ifGenerationMatch = 0
      }
    }
    let object = try await client.upload(data, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */0")
    #expect(requests[1].value(forHTTPHeaderField: "x-goog-hash") == "crc32c=AAAAAA==")
  }

  /// Tests resumable upload of an empty local file (0 bytes) when threshold is 0.
  @Test func resumableUploadZeroByteFileSourceSuccess() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
    let fileURL = tempDirectory.appendingPathComponent("empty_resumable_\(UUID().uuidString).txt")
    try Data().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-resumable-empty-file"

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&upload_id=zero-file-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    registry.register(
      response: .success(
        statusCode: 200, data: makeObjectJSON(name: objectName, bucket: bucket, size: 0),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 0
    }
    let object = try await client.upload(
      fileURL, to: bucket, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == "projects/_/buckets/\(bucket)")
    #expect(object.size == 0)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "Content-Range") == "bytes */0")
    #expect(requests[1].value(forHTTPHeaderField: "x-goog-hash") == "crc32c=AAAAAA==")
  }

  /// Tests that resumable uploads work when the bucket is provided as a resource name (e.g., `projects/_/buckets/my-bucket`).
  @Test func resumableUploadWithBucketResourceName() async throws {
    let registry = MockRegistry.create()
    let rawBucket = "resumable-resource-bucket"
    let bucketResource = "projects/_/buckets/\(rawBucket)"
    let objectName = "test-resumable-resource-object"
    let data = Data(repeating: 0x42, count: 1024)
    let source = BytesSource(data: data)

    let initUrl = registry.url(
      "/upload/storage/v1/b/\(rawBucket)/o?uploadType=resumable&name=\(objectName)")
    let sessionUrl = registry.url(
      "/upload/storage/v1/b/\(rawBucket)/o?uploadType=resumable&upload_id=test-session-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": sessionUrl.absoluteString]),
      for: initUrl)

    registry.register(
      response: .success(
        statusCode: 200,
        data: makeObjectJSON(name: objectName, bucket: rawBucket, size: data.count),
        headers: nil),
      for: sessionUrl)

    let client = try makeClient(registry: registry)
    let uploadOptions = UploadOptions().with {
      $0.resumableUploadThreshold = 0
    }
    let object = try await client.upload(
      source, to: bucketResource, as: objectName, options: uploadOptions)

    #expect(object.name == objectName)
    #expect(object.bucket == bucketResource)
    #expect(object.size == Int64(data.count))

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.url?.absoluteString == initUrl.absoluteString)
  }
}

// MARK: - Test Helper Sources

/// A non-seekable computational upload source generating deterministic bytes on-demand.
private struct DynamicComputationSource: UploadSource {
  let chunkSize: Int
  let totalChunks: Int
  let totalSize: UInt64?
  private var currentChunk: Int = 0

  init(chunkSize: Int, totalChunks: Int, totalSize: UInt64?) {
    self.chunkSize = chunkSize
    self.totalChunks = totalChunks
    self.totalSize = totalSize
  }

  mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard currentChunk < totalChunks else { return nil }
    let count = min(maxBytes, chunkSize)
    let byteVal = UInt8((currentChunk + 1) % 256)
    currentChunk += 1
    return ByteBuffer(Data(repeating: byteVal, count: count))
  }
}

/// A seekable computational upload source that can re-initialize its generator to any offset.
private struct SeekableComputationSource: SeekableUploadSource {
  let chunkSize: Int
  let totalChunks: Int
  let totalSize: UInt64?
  private var currentOffset: UInt64 = 0

  init(chunkSize: Int, totalChunks: Int) {
    self.chunkSize = chunkSize
    self.totalChunks = totalChunks
    self.totalSize = UInt64(chunkSize * totalChunks)
  }

  mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard let totalSize = totalSize, currentOffset < totalSize else { return nil }
    let bytesToRead = min(UInt64(maxBytes), totalSize - currentOffset)
    guard bytesToRead > 0 else { return nil }
    let chunkIndex = Int(currentOffset / UInt64(chunkSize))
    let byteVal = UInt8((chunkIndex + 1) % 256)
    currentOffset += bytesToRead
    return ByteBuffer(Data(repeating: byteVal, count: Int(bytesToRead)))
  }

  mutating func seek(to offset: UInt64) async throws {
    guard let total = totalSize, offset <= total else {
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
