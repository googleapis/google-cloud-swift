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
import GoogleCloudGax
@testable import GoogleCloudStorage
import NIOCore
import Testing

func integrationTestsEnabled() -> Bool {
  ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil
    && ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] != nil
}

@Suite(.enabled(if: integrationTestsEnabled()))
struct StorageClientIntegrationTests {
  let bucketName = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!

  @Test func testFileUpload() async throws {
    let objectName = "test-upload-\(UUID().uuidString).txt"

    let content = "Hello Google Cloud Storage from Swift!"
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    let task = storage.upload(fileURL, to: bucketName, as: objectName)

    var statusUpdates = [UploadStatus]()
    for await status in task.makeStatusStream() {
      statusUpdates.append(status)
      print(
        "Status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
      )
    }

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(content.utf8.count))
    // Simple Upload - only 1 status update
    #expect(statusUpdates.count == 1)

    print("Upload successful: \(object)")
  }

  @Test func testFileDownload() async throws {
    let objectName = "test-download-\(UUID().uuidString).txt"
    let content = "Hello Google Cloud Storage file download integration test!"
    let data = Data(content.utf8)

    let storage = try StorageClient()

    let uploadTask = storage.upload(data, to: bucketName, as: objectName)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)

    let result = storage.readObject(from: bucketName, object: objectName)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(data.count))
    #expect(metadata.generation == UInt64(uploadedObject.generation))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == data)
    let downloadedString = String(data: downloadedData, encoding: .utf8)
    #expect(downloadedString == content)

    print("File download integration test successful: \(metadata)")
  }

  @Test func testFailedDownloadPrecondition() async throws {
    let objectName = "test-precondition-failed-\(UUID().uuidString).txt"
    let content = "Hello GCS precondition failure integration test!"
    let data = Data(content.utf8)

    let storage = try StorageClient()

    let uploadTask = storage.upload(data, to: bucketName, as: objectName)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)

    let mismatchedGeneration = uploadedObject.generation + 1
    let options = ReadObjectOptions().with {
      $0.preconditions = StoragePreconditions().with {
        $0.ifGenerationMatch = mismatchedGeneration
      }
    }

    do {
      _ = try await storage.readObject(from: bucketName, object: objectName, options: options)
        .metadata
      Issue.record("Expected download to fail with 412 Precondition Failed, but it succeeded")
    } catch DownloadError.unexpectedServerResponse(let statusCode, let message) {
      #expect(statusCode == 412)
      print("GCS correctly returned 412 Precondition Failed: \(message)")
    } catch {
      Issue.record("Expected DownloadError.unexpectedServerResponse(412), got \(error)")
    }
  }

  @Test(arguments: [
    "folder/subfolder/file.json",
    "file with spaces.txt",
    "file&with&ampersands.txt",
    "file?with?questionmarks.txt",
    "file#with#hashes.txt",
    "folder/subfolder/file with & and ? and #.json",
  ])
  func testUploadAndDownloadSpecialCharacters(pathSuffix: String) async throws {
    let uniqueId = UUID().uuidString
    let objectName = "test-special-\(uniqueId)/\(pathSuffix)"
    let content = "Integration test payload for special characters: \(pathSuffix)"
    let data = Data(content.utf8)

    let storage = try StorageClient()

    let uploadTask = storage.upload(data, to: bucketName, as: objectName)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)
    #expect(uploadedObject.size == Int64(data.count))

    let result = storage.readObject(from: bucketName, object: objectName)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(data.count))
    #expect(metadata.generation == UInt64(uploadedObject.generation))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == data)
    let downloadedString = String(data: downloadedData, encoding: .utf8)
    #expect(downloadedString == content)
  }

  @Test func testLargeFileUpload() async throws {
    let objectName = "test-large-upload-\(UUID().uuidString).bin"

    // 10MB file to trigger resumable upload (threshold is 8MB)
    let fileSize = 10 * 1024 * 1024
    let data = Data(count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    let task = storage.upload(fileURL, to: bucketName, as: objectName)

    var statusUpdates = [UploadStatus]()
    for await status in task.makeStatusStream() {
      statusUpdates.append(status)
      print(
        "Status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
      )
    }

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(fileSize))

    // Verify that it was a resumable upload by checking for upload ID in status updates
    let hasUploadId = statusUpdates.contains { $0.uploadId != nil }
    #expect(hasUploadId)
    // Statuses: Start -> First Chunk -> Final Upload
    #expect(statusUpdates.count == 3)

    print("Large upload successful: \(object)")
  }

  @Test func testFailedResumableUploadAndResume() async throws {
    let objectName = "test-failed-resumable-\(UUID().uuidString).bin"

    let fileSize = 10 * 1024 * 1024  // 10MB
    let data = Data(repeating: 42, count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()

    // Set chunk size to 2MB and configure failing source to throw after 4MB read
    let chunkSize = 2 * 1024 * 1024
    let failAfterBytes = Int64(4 * 1024 * 1024)
    let options = UploadOptions().with { $0.chunkSize = chunkSize }
    let failingSource = FailingUploadSource(fileURL: fileURL, failAfterBytes: failAfterBytes)

    let task = storage.upload(failingSource, to: bucketName, as: objectName, options: options)

    var statusUpdates = [UploadStatus]()
    for await status in task.makeStatusStream() {
      statusUpdates.append(status)
      print(
        "Failed test status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
      )
    }

    // Verify that upload task failed with SimulatedUploadError
    do {
      _ = try await task.value
      Issue.record("Expected upload to fail, but it succeeded")
    } catch is FailingUploadSource.SimulatedUploadError {
      // Expected error
    } catch {
      Issue.record("Expected SimulatedUploadError, got \(error)")
    }

    // Extract the upload ID from the recorded status updates
    let uploadId = statusUpdates.compactMap(\.uploadId).first
    #expect(uploadId != nil)
    guard let uploadId = uploadId else {
      Issue.record("No uploadId captured before upload failure")
      return
    }

    // ChecksummedSource looks ahead 1 chunk to detect the final chunk.
    // Reading chunk 1 (2MB) triggers a lookahead read for chunk 2 (2MB), advancing bytesRead to 4MB.
    // When chunk 2 is processed, the lookahead for chunk 3 fails because bytesRead reached 4MB.
    // Thus, GCS receives 1 chunk (2MB) before the upload task fails.
    let expectedUploadedBytes = Int64(2 * 1024 * 1024)
    let lastUploadedBytes = statusUpdates.last?.bytesUploaded ?? 0
    #expect(lastUploadedBytes == expectedUploadedBytes)

    // Now resume the upload using full FileSource and original uploadId
    let fileSource = FileSource(fileURL: fileURL)
    let resumeTask = storage.resumeUpload(fileSource, uploadId: uploadId, options: options)

    var resumeStatusUpdates = [UploadStatus]()
    for await status in resumeTask.makeStatusStream() {
      resumeStatusUpdates.append(status)
      print(
        "Resumed status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
      )
    }

    let object = try await resumeTask.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(fileSize))

    // Verify resume status starts at the 2MB offset reported by GCS
    if let firstResumeStatus = resumeStatusUpdates.first {
      #expect(firstResumeStatus.bytesUploaded == expectedUploadedBytes)
    }

    print("Resumed upload successful: \(object)")
  }

  @Test func testResumedFailedUploadWithChecksumValidation() async throws {
    let objectName = "test-resumed-checksum-\(UUID().uuidString).bin"

    let fileSize = 10 * 1024 * 1024  // 10MB payload
    let data = Data(repeating: 55, count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()

    // Set 2MB chunk size and fail source after 4MB read
    let chunkSize = 2 * 1024 * 1024
    let failAfterBytes = Int64(4 * 1024 * 1024)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto)
      $0.chunkSize = chunkSize
    }
    let failingSource = FailingUploadSource(fileURL: fileURL, failAfterBytes: failAfterBytes)

    let task = storage.upload(
      failingSource, to: bucketName, as: objectName, options: uploadOptions)

    var statusUpdates = [UploadStatus]()
    for await status in task.makeStatusStream() {
      statusUpdates.append(status)
    }

    do {
      _ = try await task.value
      Issue.record("Expected upload to fail, but it succeeded")
    } catch is FailingUploadSource.SimulatedUploadError {
      // Expected error
    } catch {
      Issue.record("Expected SimulatedUploadError, got \(error)")
    }

    guard let uploadId = statusUpdates.compactMap(\.uploadId).first else {
      Issue.record("No uploadId captured before failure")
      return
    }

    // Resume upload with automatic CRC32C checksum calculation handled by our SDK
    let resumeOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto)
      $0.chunkSize = chunkSize
    }
    let fileSource = FileSource(fileURL: fileURL)
    let resumeTask = storage.resumeUpload(fileSource, uploadId: uploadId, options: resumeOptions)

    let object = try await resumeTask.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(fileSize))
    print("Resumed upload with automatic checksum validation successful: \(object)")
  }

  @Test func testResumedFailedUploadWithNewSourceInstance() async throws {
    let objectName = "test-resumed-new-source-\(UUID().uuidString).bin"

    let fileSize = 10 * 1024 * 1024  // 10MB payload
    let data = Data(repeating: 77, count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()

    let chunkSize = 2 * 1024 * 1024
    let failAfterBytes = Int64(4 * 1024 * 1024)
    let uploadOptions = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto)
      $0.chunkSize = chunkSize
    }
    let failingSource = FailingUploadSource(fileURL: fileURL, failAfterBytes: failAfterBytes)

    let task = storage.upload(
      failingSource, to: bucketName, as: objectName, options: uploadOptions)

    var statusUpdates = [UploadStatus]()
    for await status in task.makeStatusStream() {
      statusUpdates.append(status)
    }

    do {
      _ = try await task.value
      Issue.record("Expected upload to fail, but it succeeded")
    } catch is FailingUploadSource.SimulatedUploadError {
      // Expected error
    } catch {
      Issue.record("Expected SimulatedUploadError, got \(error)")
    }

    guard let uploadId = statusUpdates.compactMap(\.uploadId).first else {
      Issue.record("No uploadId captured before failure")
      return
    }

    // Resume upload with a brand new source instance referencing the same file
    let newSourceInstance = FileSource(fileURL: fileURL)
    let resumeTask = storage.resumeUpload(
      newSourceInstance, uploadId: uploadId, options: uploadOptions)

    let object = try await resumeTask.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(fileSize))
    #expect(object.checksums?.crc32C != nil)
    print("Resumed upload with new source instance and CRC32C checksumming successful: \(object)")
  }

  @Test func testSimpleUploadWithChecksumValidation() async throws {
    let storage = try StorageClient()

    for validation in [ChecksumValidation.crc32c, ChecksumValidation.md5] {
      let objectName = "test-checksum-simple-\(UUID().uuidString).txt"
      let content = "Hello Google Cloud Storage checksum validation: \(validation)"
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
      try content.write(to: fileURL, atomically: true, encoding: .utf8)
      defer {
        try? FileManager.default.removeItem(at: fileURL)
      }

      let options = UploadOptions().with { $0.validation = validation }
      let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

      let object = try await task.value
      #expect(object.bucket == bucketName)
      #expect(object.name == objectName)
      #expect(object.size == Int64(content.utf8.count))

      print("Simple upload with \(validation) successful: \(object)")
    }
  }

  @Test func testResumableUploadWithChecksumValidation() async throws {
    let storage = try StorageClient()

    for validation in [ChecksumValidation.crc32c, ChecksumValidation.md5] {
      let objectName = "test-checksum-resumable-\(UUID().uuidString).bin"
      let fileSize = 10 * 1024 * 1024
      var data = Data(count: fileSize)
      for i in 0..<fileSize {
        data[i] = UInt8(i % 256)
      }
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
      try data.write(to: fileURL)
      defer {
        try? FileManager.default.removeItem(at: fileURL)
      }

      let options = UploadOptions().with { $0.validation = validation }
      let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

      let object = try await task.value
      #expect(object.bucket == bucketName)
      #expect(object.name == objectName)
      #expect(object.size == Int64(fileSize))

      print("Resumable upload with \(validation) successful: \(object)")
    }
  }

  @Test func testMultipleChecksumsUpload() async throws {
    let objectName = "test-multiple-checksums-\(UUID().uuidString).txt"

    let content = "Hello Google Cloud Storage with multiple checksums!"
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    let options = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    }
    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(content.utf8.count))

    print("Multiple checksums upload successful: \(object)")
  }

  @Test func testBadChecksumUploadRejection() async throws {
    let objectName = "test-bad-checksum-\(UUID().uuidString).bin"

    // 10MB file to trigger resumable upload where x-goog-hash is validated by GCS
    let fileSize = 10 * 1024 * 1024
    let data = Data(repeating: 42, count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    // Provide an intentionally invalid pre-calculated CRC32C checksum ("AAAAAA==")
    let options = UploadOptions().with {
      $0.checksums = ChecksumOptions(crc32c: "AAAAAA==")
    }
    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    do {
      _ = try await task.value
      Issue.record("Expected GCS to reject upload with bad checksum, but it succeeded")
    } catch RequestError.service(let serviceError) {
      #expect(serviceError.message.contains("doesn't match"))
      print("GCS correctly rejected bad checksum: \(serviceError.message)")
    } catch RequestError.http(let details) {
      #expect(details.http_status_code == 400)
      print(
        "GCS correctly rejected bad checksum: \(String(data: details.payload, encoding: .utf8) ?? "")"
      )
    } catch {
      Issue.record("Expected RequestError, but got \(error)")
    }
  }

  @Test func testCSEKUploadAndDownload() async throws {
    let objectName = "test-csek-upload-download-\(UUID().uuidString).txt"
    let content = "Hello Google Cloud Storage CSEK upload and download integration test!"
    let data = Data(content.utf8)

    let keyBytes: [UInt8] = (0..<32).map { UInt8(($0 * 17 + 23) % 256) }
    let csek = try CustomerEncryptionKeyOptions(keyBytes: keyBytes)

    let storage = try StorageClient()

    // 1. Upload object encrypted with CSEK
    let uploadOptions = UploadOptions().with {
      $0.customerEncryptionKey = csek
    }
    let uploadTask = storage.upload(data, to: bucketName, as: objectName, options: uploadOptions)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)
    #expect(uploadedObject.size == Int64(data.count))
    #expect(uploadedObject.customerEncryption?.keySha256 == csek.keyHashBase64)

    // 2. Attempt download without CSEK key (GCS rejects with 400 Bad Request)
    do {
      _ = try await storage.readObject(from: bucketName, object: objectName).metadata
      Issue.record("Expected download without CSEK key to fail")
    } catch DownloadError.unexpectedServerResponse(let statusCode, _) {
      #expect(statusCode == 400)
    } catch {
      Issue.record("Expected DownloadError.unexpectedServerResponse, got \(error)")
    }

    // 3. Download object with matching CSEK key
    let downloadOptions = ReadObjectOptions().with {
      $0.customerEncryptionKey = csek
    }
    let result = storage.readObject(
      from: bucketName, object: objectName, options: downloadOptions)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(data.count))
    #expect(metadata.generation == UInt64(uploadedObject.generation))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == data)
    let downloadedString = String(data: downloadedData, encoding: .utf8)
    #expect(downloadedString == content)

    print("CSEK upload and download successful: \(metadata)")
  }

  @Test func testCSEKSimpleUpload() async throws {
    let objectName = "test-csek-simple-\(UUID().uuidString).txt"

    let content = "Hello Google Cloud Storage CSEK simple upload!"
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let keyBytes: [UInt8] = (0..<32).map { UInt8(($0 * 11 + 17) % 256) }
    let csek = try CustomerEncryptionKeyOptions(keyBytes: keyBytes)

    let storage = try StorageClient()
    let options = UploadOptions().with {
      $0.customerEncryptionKey = csek
    }
    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(content.utf8.count))
    #expect(object.customerEncryption?.keySha256 == csek.keyHashBase64)

    print("CSEK simple upload successful: \(object)")
  }

  @Test func testCSEKResumableUpload() async throws {
    let objectName = "test-csek-resumable-\(UUID().uuidString).bin"

    let fileSize = 10 * 1024 * 1024  // 10MB to trigger resumable upload
    let data = Data(repeating: 0x5A, count: fileSize)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try data.write(to: fileURL)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let keyData = Data((0..<32).map { UInt8(($0 * 13 + 37) % 256) })
    let csek = try CustomerEncryptionKeyOptions(key: keyData)

    let storage = try StorageClient()
    let options = UploadOptions().with {
      $0.customerEncryptionKey = csek
    }
    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == Int64(fileSize))
    #expect(object.customerEncryption?.keySha256 == csek.keyHashBase64)

    // Verify download of large CSEK-encrypted file
    let downloadOptions = ReadObjectOptions().with {
      $0.customerEncryptionKey = csek
    }
    let result = storage.readObject(
      from: bucketName, object: objectName, options: downloadOptions)
    let metadata = try await result.metadata
    #expect(metadata.size == UInt64(fileSize))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData == data)

    print("CSEK resumable upload and download successful: \(object)")
  }

  @Test func testUploadWithMetadata() async throws {
    let objectName = "test-metadata-\(UUID().uuidString).txt"

    let content = "Hello Google Cloud Storage metadata upload!"
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    let metadata = UploadMetadata().with {
      $0.contentType = "text/plain"
      $0.contentLanguage = "en"
      $0.cacheControl = "public, max-age=3600"
      $0.customMetadata = ["environment": "integration-test", "author": "swift-sdk"]
    }
    let options = UploadOptions().with {
      $0.metadata = metadata
    }

    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.contentType == "text/plain")
    #expect(object.contentLanguage == "en")
    #expect(object.cacheControl == "public, max-age=3600")
    #expect(object.metadata["environment"] == "integration-test")
    #expect(object.metadata["author"] == "swift-sdk")

    print("Upload with metadata successful: \(object)")
  }

  @Test func testUploadWithObjectContexts() async throws {
    let objectName = "test-contexts-\(UUID().uuidString).txt"

    let content = "Hello Google Cloud Storage object contexts upload!"
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    let storage = try StorageClient()
    let options = UploadOptions().with {
      $0.metadata = UploadMetadata().with {
        $0.contexts = ObjectContexts(customValues: [
          "environment": "integration-test", "team": "swift-sdk",
        ])
      }
    }

    let task = storage.upload(fileURL, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.contexts?.custom["environment"]?.value == "integration-test")
    #expect(object.contexts?.custom["team"]?.value == "swift-sdk")

    print("Upload with object contexts successful: \(object)")
  }

  @Test func testDynamicSourceCompletelyEmptyUpload() async throws {
    let objectName = "test-dynamic-empty-\(UUID().uuidString).bin"

    let source = IntegrationDynamicSource(
      chunkSize: 4 * 1024 * 1024, totalChunks: 0, totalSize: nil)

    let storage = try StorageClient()
    let task = storage.upload(source, to: bucketName, as: objectName)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == 0)

    print("Dynamic source completely empty upload successful: \(object)")
  }

  @Test func testDynamicSourceLastChunkEmptyUpload() async throws {
    let objectName = "test-dynamic-last-chunk-empty-\(UUID().uuidString).bin"

    let chunkSize = 5 * 1024 * 1024  // 5MB chunks
    let totalChunks = 2
    let expectedTotalSize = Int64(chunkSize * totalChunks)  // 10MB

    let source = IntegrationDynamicSource(
      chunkSize: chunkSize, totalChunks: totalChunks, totalSize: nil)

    let storage = try StorageClient()
    let options = UploadOptions().with { $0.chunkSize = chunkSize }
    let task = storage.upload(source, to: bucketName, as: objectName, options: options)

    let object = try await task.value
    #expect(object.bucket == bucketName)
    #expect(object.name == objectName)
    #expect(object.size == expectedTotalSize)

    print("Dynamic source with last chunk empty upload successful: \(object)")
  }
}

@Suite(.enabled(if: integrationTestsEnabled()))
struct StorageClientGzipDownloadIntegrationTests {
  let bucketName = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!

  private static let rawGzipContent =
    "Hello Google Cloud Storage decompressive transcoding integration test! Testing gzip payload and transcoding behavior across different options."
  private static let rawGzipData = Data(rawGzipContent.utf8)
  private static let compressedGzipData = Data([
    0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x55, 0x8C, 0xB1, 0x0D, 0x02,
    0x41, 0x0C, 0x04, 0x5B, 0x59, 0x1A, 0xA0, 0x09, 0x02, 0xC8, 0xA1, 0x01, 0xF3, 0xE7, 0x3F,
    0x2C, 0x1D, 0xDE, 0x93, 0x6D, 0x5E, 0x82, 0xEA, 0xE1, 0x43, 0x92, 0x49, 0x46, 0x33, 0x17,
    0x1D, 0x83, 0x38, 0x93, 0x7D, 0x28, 0x4E, 0x83, 0xAF, 0x86, 0x6B, 0x31, 0xA4, 0x2B, 0x9A,
    0x2E, 0x7C, 0xCE, 0xD0, 0x4C, 0xDB, 0x14, 0x15, 0xE2, 0xB9, 0xB0, 0x99, 0x77, 0x98, 0x97,
    0xF6, 0x90, 0x32, 0x3A, 0x4A, 0xB3, 0x0E, 0xB8, 0xFD, 0xB8, 0x9B, 0xFE, 0xB1, 0x89, 0x29,
    0xEF, 0x41, 0x69, 0x10, 0x6F, 0x7F, 0xD9, 0x5D, 0x1F, 0xB2, 0x19, 0x03, 0xB2, 0x04, 0x33,
    0xD1, 0x6C, 0x5D, 0x35, 0xD4, 0x0B, 0x9C, 0xFB, 0x2B, 0x8F, 0x5F, 0xA4, 0x83, 0xBE, 0x71,
    0x8E, 0x00, 0x00, 0x00,
  ])

  @Test func testDownloadGzipAllowDecompressiveTranscoding() async throws {
    let objectName = "test-gzip-transcode-\(UUID().uuidString).txt"
    let storage = try StorageClient()

    let uploadMetadata = UploadMetadata().with {
      $0.contentEncoding = "gzip"
      $0.contentType = "text/plain"
    }
    let uploadOptions = UploadOptions().with {
      $0.metadata = uploadMetadata
    }

    let uploadTask = storage.upload(
      Self.compressedGzipData, to: bucketName, as: objectName, options: uploadOptions)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)
    #expect(uploadedObject.contentEncoding == "gzip")

    // Standard download request (decompressive transcoding allowed)
    let downloadOptions = ReadObjectOptions().with {
      $0.enableDecompressiveTranscoding = true
    }
    let result = storage.readObject(
      from: bucketName, object: objectName, options: downloadOptions)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    // GCS serves uncompressed raw content
    #expect(downloadedData == Self.rawGzipData)
    let downloadedString = String(data: downloadedData, encoding: .utf8)
    #expect(downloadedString == Self.rawGzipContent)

    print("Gzip allow decompressive transcoding integration test successful: \(metadata)")
  }

  @Test func testDownloadGzipPreventTranscodingViaRequestHeader() async throws {
    let objectName = "test-gzip-no-transcode-header-\(UUID().uuidString).txt"
    let storage = try StorageClient()

    let uploadMetadata = UploadMetadata().with {
      $0.contentEncoding = "gzip"
      $0.contentType = "text/plain"
    }
    let uploadOptions = UploadOptions().with {
      $0.metadata = uploadMetadata
    }

    let uploadTask = storage.upload(
      Self.compressedGzipData, to: bucketName, as: objectName, options: uploadOptions)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)
    #expect(uploadedObject.contentEncoding == "gzip")

    // Prevent transcoding via request header (enableDecompressiveTranscoding = false)
    let downloadOptions = ReadObjectOptions().with {
      $0.enableDecompressiveTranscoding = false
    }
    let result = storage.readObject(
      from: bucketName, object: objectName, options: downloadOptions)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)
    #expect(metadata.contentEncoding == "gzip")

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    // Downloader receives the original gzip-compressed file
    #expect(downloadedData == Self.compressedGzipData)
    #expect(metadata.size == UInt64(Self.compressedGzipData.count))

    print(
      "Gzip prevent transcoding via request header integration test successful: \(metadata)"
    )
  }

  @Test func testDownloadGzipPreventTranscodingViaCacheControlNoTransform() async throws {
    let objectName = "test-gzip-cache-control-no-transform-\(UUID().uuidString).txt"
    let storage = try StorageClient()

    let uploadMetadata = UploadMetadata().with {
      $0.contentEncoding = "gzip"
      $0.cacheControl = "no-transform"
      $0.contentType = "text/plain"
    }
    let uploadOptions = UploadOptions().with {
      $0.metadata = uploadMetadata
    }

    let uploadTask = storage.upload(
      Self.compressedGzipData, to: bucketName, as: objectName, options: uploadOptions)
    let uploadedObject = try await uploadTask.value
    #expect(uploadedObject.bucket == bucketName)
    #expect(uploadedObject.name == objectName)
    #expect(uploadedObject.contentEncoding == "gzip")
    #expect(uploadedObject.cacheControl == "no-transform")

    // Standard download request without special options
    let result = storage.readObject(from: bucketName, object: objectName)
    let metadata = try await result.metadata
    #expect(metadata.bucket == bucketName)
    #expect(metadata.object == objectName)
    #expect(metadata.contentEncoding == "gzip")

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    // Downloader receives the original gzip-compressed file because of Cache-Control: no-transform
    #expect(downloadedData == Self.compressedGzipData)
    #expect(metadata.size == UInt64(Self.compressedGzipData.count))

    print(
      "Gzip prevent transcoding via Cache-Control no-transform integration test successful: \(metadata)"
    )
  }
}

@Suite(.enabled(if: integrationTestsEnabled()))
struct StorageClientRangedDownloadIntegrationTests {
  struct FixtureState: Sendable {
    let bucketName: String
    let objectName: String
    let totalSize: UInt64
    let uploadedObject: Object
  }

  let bucketName = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!

  static let sharedFixture = Task<FixtureState, any Error> {
    let bucket =
      ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"]!
    let objName = "test-ranged-download-\(UUID().uuidString).txt"
    let content = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let data = Data(content.utf8)

    let storageClient = try StorageClient()
    let uploadTask = storageClient.upload(data, to: bucket, as: objName)
    let obj = try await uploadTask.value
    #expect(obj.bucket == bucket)
    #expect(obj.name == objName)

    return FixtureState(
      bucketName: bucket,
      objectName: objName,
      totalSize: UInt64(data.count),
      uploadedObject: obj
    )
  }

  @Test(arguments: [
    (ReadObjectRange.bounded(start: 10, end: 19), "abcdefghij"),
    (ReadObjectRange.fromOffset(36), "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
    (ReadObjectRange.prefix(10), "0123456789"),
    (ReadObjectRange.suffix(10), "QRSTUVWXYZ"),
    (ReadObjectRange(5...15), "56789abcdef"),
    (ReadObjectRange.entire, "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"),
  ])
  func testRangedDownload(range: ReadObjectRange, expectedContent: String) async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()
    let options = ReadObjectOptions().with {
      $0.range = range
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    let metadata = try await result.metadata

    #expect(metadata.size == fixture.totalSize)
    #expect(metadata.generation == UInt64(fixture.uploadedObject.generation))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    let downloadedString = String(data: downloadedData, encoding: .utf8) ?? ""
    #expect(downloadedString == expectedContent)
  }

  @Test func testRangedDownloadZeroCount() async throws {
    let fixture = try await Self.sharedFixture.value
    let storage = try StorageClient()
    let options = ReadObjectOptions().with {
      $0.range = .prefix(0)
    }
    let result = storage.readObject(
      from: fixture.bucketName, object: fixture.objectName, options: options)
    let metadata = try await result.metadata

    #expect(metadata.size == fixture.totalSize)
    #expect(metadata.generation == UInt64(fixture.uploadedObject.generation))

    var downloadedData = Data()
    for try await chunk in result.body {
      downloadedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloadedData.isEmpty)
  }

  @Test(arguments: [
    ReadObjectRange.prefix(0),
    ReadObjectRange.suffix(0),
    ReadObjectRange.bounded(start: 10, end: 19),
    ReadObjectRange.fromOffset(36),
    ReadObjectRange.prefix(10),
    ReadObjectRange.suffix(10),
    ReadObjectRange.entire,
  ])
  func testRangedDownloadNonExistentObject(range: ReadObjectRange) async throws {
    let storage = try StorageClient()
    let options = ReadObjectOptions().with {
      $0.range = range
    }
    do {
      _ = try await storage.readObject(
        from: bucketName,
        object: "non-existent-\(UUID().uuidString).txt",
        options: options
      ).metadata
      Issue.record("Expected reading non-existent object to throw 404")
    } catch DownloadError.unexpectedServerResponse(let statusCode, _) {
      #expect(statusCode == 404)
    } catch {
      Issue.record("Expected DownloadError.unexpectedServerResponse, got \(error)")
    }
  }
}

private struct IntegrationDynamicSource: UploadSource {
  let chunkSize: Int
  let totalChunks: Int
  let totalSize: Int64?
  private var currentChunk: Int = 0

  init(chunkSize: Int, totalChunks: Int, totalSize: Int64? = nil) {
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

private struct FailingUploadSource: SeekableUploadSource {
  struct SimulatedUploadError: Error {}

  private var fileSource: FileSource
  let failAfterBytes: Int64
  private var bytesRead: Int64 = 0

  var totalSize: Int64? {
    fileSource.totalSize
  }

  init(fileURL: URL, failAfterBytes: Int64) {
    self.fileSource = FileSource(fileURL: fileURL)
    self.failAfterBytes = failAfterBytes
  }

  mutating func read(maxBytes: Int) async throws -> Data? {
    guard bytesRead < failAfterBytes else {
      throw SimulatedUploadError()
    }
    let bytesToRead = min(Int64(maxBytes), failAfterBytes - bytesRead)
    guard let chunk = try await fileSource.read(maxBytes: Int(bytesToRead)) else {
      return nil
    }
    bytesRead += Int64(chunk.count)
    return chunk
  }

  mutating func seek(to offset: Int64) async throws {
    try await fileSource.seek(to: offset)
    bytesRead = offset
  }
}
