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
@testable import GoogleCloudStorage
import Testing

#if IntegrationTests

  @Suite struct StorageClientIntegrationTests {
    @Test func testFileUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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

    @Test func testLargeFileUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      #expect(object.crc32c != nil)
      print("Resumed upload with new source instance and CRC32C checksumming successful: \(object)")
    }

    @Test func testSimpleUploadWithChecksumValidation() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"

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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"

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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      } catch UploadError.checksumMismatch(let localChecksum, let serverChecksum) {
        #expect(localChecksum == "crc32c=AAAAAA==")
        #expect(!serverChecksum.isEmpty)
        print(
          "GCS correctly rejected bad checksum: local=\(localChecksum), server=\(serverChecksum)")
      } catch {
        Issue.record("Expected UploadError.checksumMismatch, but got \(error)")
      }
    }

    @Test func testCSEKSimpleUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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

      print("CSEK resumable upload successful: \(object)")
    }

    @Test func testUploadWithMetadata() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      #expect(object.customMetadata?["environment"] == "integration-test")
      #expect(object.customMetadata?["author"] == "swift-sdk")

      print("Upload with metadata successful: \(object)")
    }

    @Test func testDynamicSourceCompletelyEmptyUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
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

#endif
