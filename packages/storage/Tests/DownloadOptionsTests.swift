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
import Testing

@Suite struct DownloadOptionsTests {
  @Test func readRangeHeaderValues() {
    #expect(ReadObjectRange.entire.headerValue == nil)
    #expect(ReadObjectRange.fromOffset(1024).headerValue == "bytes=1024-")
    #expect(ReadObjectRange.prefix(500).headerValue == "bytes=0-499")
    #expect(ReadObjectRange.prefix(0).headerValue == "bytes=0-0")
    #expect(ReadObjectRange.suffix(100).headerValue == "bytes=-100")
    #expect(ReadObjectRange.bounded(10...50).headerValue == "bytes=10-50")
    #expect(ReadObjectRange(10...50).headerValue == "bytes=10-50")
    #expect(ReadObjectRange(10...50) == ReadObjectRange.bounded(10...50))
    #expect(ReadObjectRange(10...).headerValue == "bytes=10-")
    #expect(ReadObjectRange(...50).headerValue == "bytes=0-50")
    #expect(ReadObjectRange(start: 10, end: 50) == ReadObjectRange.bounded(10...50))
    #expect(ReadObjectRange(start: 50, end: 10) == nil)
  }

  @Test func readObjectOptionsDefaults() throws {
    let defaultOptions = ReadObjectOptions.default
    #expect(defaultOptions.generation == nil)
    #expect(defaultOptions.preconditions == nil)
    #expect(defaultOptions.customerEncryptionKey == nil)
    #expect(defaultOptions.range == .entire)
    #expect(defaultOptions.enableDecompressiveTranscoding == true)
    #expect(defaultOptions.checksums == .default)
    #expect(defaultOptions.resumePolicy == nil)
    #expect(defaultOptions.backoffPolicy == nil)
  }

  @Test func readObjectOptionsWithBuilder() throws {
    let preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = 123
    }
    let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
    let options = ReadObjectOptions().with {
      $0.generation = 456
      $0.preconditions = preconditions
      $0.customerEncryptionKey = csek
      $0.range = .bounded(0...1024)
      $0.enableDecompressiveTranscoding = false
      $0.resumePolicy = NeverResume<DownloadDetails>()
      $0.checksums = .none
    }

    #expect(options.generation == 456)
    #expect(options.preconditions?.ifGenerationMatch == 123)
    #expect(options.customerEncryptionKey == csek)
    #expect(options.range == ReadObjectRange.bounded(0...1024))
    #expect(options.enableDecompressiveTranscoding == false)
    #expect(options.resumePolicy != nil)
    #expect(options.checksums == .none)
  }

  @Test func readObjectMetadataProperties() {
    let now = Date()
    let metadata = ReadObjectMetadata().with {
      $0.bucket = "my-bucket"
      $0.object = "my-object.txt"
      $0.size = 2048
      $0.generation = 10
      $0.metageneration = 2
      $0.etag = "etag-123"
      $0.crc32c = "crc-456"
      $0.md5Hash = "md5-789"
      $0.contentType = "text/plain"
      $0.contentEncoding = "gzip"
      $0.contentDisposition = "inline"
      $0.storageClass = "STANDARD"
      $0.updated = now
    }

    #expect(metadata.bucket == "my-bucket")
    #expect(metadata.object == "my-object.txt")
    #expect(metadata.size == 2048)
    #expect(metadata.generation == 10)
    #expect(metadata.metageneration == 2)
    #expect(metadata.etag == "etag-123")
    #expect(metadata.crc32c == "crc-456")
    #expect(metadata.md5Hash == "md5-789")
    #expect(metadata.contentType == "text/plain")
    #expect(metadata.contentEncoding == "gzip")
    #expect(metadata.contentDisposition == "inline")
    #expect(metadata.storageClass == "STANDARD")
    #expect(metadata.updated == now)
  }

  @Test func calculateResumeRangeScenarios() {
    // Entire
    #expect(
      calculateResumeRange(originalRange: .entire, bytesReceived: 0, totalSize: 1000)
        == .fromOffset(0))
    #expect(
      calculateResumeRange(originalRange: .entire, bytesReceived: 500, totalSize: 1000)
        == .fromOffset(500))

    // From offset
    #expect(
      calculateResumeRange(originalRange: .fromOffset(100), bytesReceived: 50, totalSize: 1000)
        == .fromOffset(150))

    // Prefix
    #expect(
      calculateResumeRange(originalRange: .prefix(100), bytesReceived: 40, totalSize: 1000)
        == .bounded(40...99))
    #expect(
      calculateResumeRange(originalRange: .prefix(100), bytesReceived: 100, totalSize: 1000) == nil)
    #expect(
      calculateResumeRange(originalRange: .prefix(100), bytesReceived: 120, totalSize: 1000) == nil)

    // Bounded
    #expect(
      calculateResumeRange(
        originalRange: .bounded(10...50), bytesReceived: 20, totalSize: 1000)
        == .bounded(30...50))
    #expect(
      calculateResumeRange(
        originalRange: .bounded(10...50), bytesReceived: 41, totalSize: 1000) == nil)

    // Suffix
    #expect(
      calculateResumeRange(originalRange: .suffix(50), bytesReceived: 10, totalSize: 200)
        == .bounded(160...199))
    #expect(
      calculateResumeRange(originalRange: .suffix(50), bytesReceived: 50, totalSize: 200) == nil)
    #expect(
      calculateResumeRange(originalRange: .suffix(50), bytesReceived: 10, totalSize: nil)
        == .fromOffset(10))
  }

  @Test func downloadErrorEquality() {
    let err1 = DownloadError.checksumMismatch(expected: "a", actual: "b", algorithm: "crc32c")
    let err2 = DownloadError.checksumMismatch(expected: "a", actual: "b", algorithm: "crc32c")
    let err3 = DownloadError.invalidRangeHeader("bytes=1-0")
    let err4 = DownloadError.resumeFailed(bytesReceived: 100, message: "failed")
    let err5 = DownloadError.resumeFailed(bytesReceived: 100, message: "failed")

    #expect(err1 == err2)
    #expect(err1 != err3)
    #expect(err4 == err5)
  }
}
