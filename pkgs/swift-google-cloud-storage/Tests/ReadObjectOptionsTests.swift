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
import GoogleGax
@testable import GoogleCloudStorage
import Testing

@Suite struct ReadObjectOptionsTests {
  @Test func readRangeHeaderValues() {
    #expect(ReadObjectRange.entire.headerValue == nil)
    #expect(ReadObjectRange(fromOffset: 1024)?.headerValue == "bytes=1024-")
    #expect(ReadObjectRange(fromOffset: 0) == ReadObjectRange.entire)
    #expect(ReadObjectRange(prefix: 500)?.headerValue == "bytes=0-499")
    #expect(ReadObjectRange(prefix: 500) == ReadObjectRange(start: 0, end: 499))
    #expect(ReadObjectRange(prefix: 500) == ReadObjectRange(range: 0...499))
    #expect(ReadObjectRange(prefix: 500) == ReadObjectRange(range: ...499))
    #expect(ReadObjectRange(prefix: 0)?.headerValue == "bytes=0-0")
    #expect(ReadObjectRange(suffix: 100)?.headerValue == "bytes=-100")
    #expect(ReadObjectRange(suffix: 0)?.headerValue == "bytes=0-0")
    #expect(ReadObjectRange(suffix: 0) == ReadObjectRange(prefix: 0))
    #expect(ReadObjectRange(suffix: 0)?.isZeroBytes == true)
    #expect(ReadObjectRange(prefix: 0)?.isZeroBytes == true)
    #expect(ReadObjectRange.entire.isZeroBytes == false)
    #expect(ReadObjectRange(range: 10...50)?.headerValue == "bytes=10-50")
    #expect(ReadObjectRange(range: 10...)?.headerValue == "bytes=10-")
    #expect(ReadObjectRange(range: 0...) == ReadObjectRange.entire)
    #expect(ReadObjectRange(range: ...50)?.headerValue == "bytes=0-50")
    #expect(ReadObjectRange(start: 10, end: 50)?.headerValue == "bytes=10-50")
    #expect(ReadObjectRange(start: 10, end: 50) == ReadObjectRange(range: 10...50))
    #expect(ReadObjectRange(start: 50, end: 10) == nil)
  }

  @Test func readObjectOptionsDefaults() throws {
    let defaultOptions = ReadObjectOptions.default
    #expect(defaultOptions.generation == nil)
    #expect(defaultOptions.preconditions == nil)
    #expect(defaultOptions.customerEncryptionKey == nil)
    #expect(defaultOptions.range == nil)
    #expect(defaultOptions.enableDecompressiveTranscoding == nil)
    #expect(defaultOptions.checksums == nil)
    #expect(defaultOptions.resumePolicy == nil)
    #expect(defaultOptions.backoffPolicy == nil)
    #expect(defaultOptions.quotaProject == nil)

    let effectiveOptions = defaultOptions.withDefaults(.default)
    #expect(effectiveOptions.range == .entire)
    #expect(effectiveOptions.enableDecompressiveTranscoding == true)
    #expect(effectiveOptions.checksums == .default)
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
      $0.range = ReadObjectRange(range: 0...1024)!
      $0.enableDecompressiveTranscoding = false
      $0.resumePolicy = NeverResume<ReadObjectDetails>()
      $0.checksums = .off
    }

    #expect(options.generation == 456)
    #expect(options.preconditions?.ifGenerationMatch == 123)
    #expect(options.customerEncryptionKey == csek)
    #expect(options.range == ReadObjectRange(range: 0...1024)!)
    #expect(options.enableDecompressiveTranscoding == false)
    #expect(options.resumePolicy != nil)
    #expect(options.checksums == .off)
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

  @Test func generationTypeInteroperability() {
    var object = Object()
    object.generation = 12345
    object.metageneration = 67890

    // ReadObjectOptions.generation can be assigned directly from Object.generation without casting
    let options = ReadObjectOptions().with {
      $0.generation = object.generation
    }
    #expect(options.generation == 12345)

    // ReadObjectMetadata generation and metageneration can be assigned directly to StoragePreconditions without casting
    let metadata = ReadObjectMetadata().with {
      $0.generation = object.generation
      $0.metageneration = object.metageneration
    }
    let preconditions = StoragePreconditions().with {
      $0.ifGenerationMatch = metadata.generation
      $0.ifMetagenerationMatch = metadata.metageneration
    }
    #expect(preconditions.ifGenerationMatch == 12345)
    #expect(preconditions.ifMetagenerationMatch == 67890)
  }

  @Test func calculateResumeRangeScenarios() {
    // Entire
    #expect(
      calculateResumeRange(originalRange: .entire, bytesReceived: 0, totalSize: 1000)
        == ReadObjectRange.entire)
    #expect(
      calculateResumeRange(originalRange: .entire, bytesReceived: 500, totalSize: 1000)
        == ReadObjectRange(fromOffset: 500)!)

    // From offset
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(fromOffset: 100)!, bytesReceived: 50, totalSize: 1000)
        == ReadObjectRange(fromOffset: 150)!)

    // Prefix
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(prefix: 0)!, bytesReceived: 0, totalSize: 1000) == nil)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(prefix: 100)!, bytesReceived: 40, totalSize: 1000)
        == ReadObjectRange(range: 40...99)!)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(prefix: 100)!, bytesReceived: 100, totalSize: 1000) == nil)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(prefix: 100)!, bytesReceived: 120, totalSize: 1000) == nil)

    // Bounded
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(range: 10...50)!, bytesReceived: 20, totalSize: 1000)
        == ReadObjectRange(range: 30...50)!)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(range: 10...50)!, bytesReceived: 41, totalSize: 1000) == nil)

    // Suffix
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 10, totalSize: 200)
        == ReadObjectRange(range: 160...199)!)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 50, totalSize: 200) == nil)
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 10, totalSize: nil)
        == ReadObjectRange(suffix: 40)!)
  }

  @Test func suffixResumeRangeWithUnknownTotalSize() {
    // Issue #728: When totalSize is unknown (nil) and bytesReceived == 0,
    // resuming a suffix range should re-request the original suffix (suffix(50)),
    // NOT the entire object from byte 0 (.entire).
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 0, totalSize: nil)
        == ReadObjectRange(suffix: 50)!)

    // When totalSize is 0 (empty object), all 0 bytes have been received, so it should return nil.
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 0, totalSize: 0)
        == nil)

    // When all requested bytes have been received, resuming should return nil,
    // NOT request from offset 50 to EOF (fromOffset(50)).
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 50, totalSize: nil)
        == nil)

    // When partial bytes (10 of 50) have been received and totalSize is unknown,
    // resuming must not request from byte 10 to EOF (fromOffset(10)).
    // It should request the remaining suffix (suffix(40)).
    #expect(
      calculateResumeRange(
        originalRange: ReadObjectRange(suffix: 50)!, bytesReceived: 10, totalSize: nil)
        == ReadObjectRange(suffix: 40)!)
  }

  @Test func readObjectOptionsQuotaProject() {
    let defaults = ReadObjectOptions.default
    #expect(defaults.quotaProject == nil)

    let custom = ReadObjectOptions().with {
      $0.quotaProject = "my-download-quota-project"
    }
    #expect(custom.quotaProject == "my-download-quota-project")
  }

  @Test func readObjectOptionsWithDefaultsInheritsAllProperties() throws {
    let defaultCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x11, count: 32))
    let defaults = ReadObjectOptions().with {
      $0.generation = 100
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 100 }
      $0.customerEncryptionKey = defaultCsek
      $0.range = ReadObjectRange(prefix: 512)
      $0.enableDecompressiveTranscoding = false
      $0.checksums = .off
      $0.resumePolicy = NeverResume<ReadObjectDetails>()
      $0.backoffPolicy = ExponentialBackoff()
      $0.quotaProject = "default-download-quota"
    }

    let resolved = ReadObjectOptions().withDefaults(defaults)
    #expect(resolved.generation == 100)
    #expect(resolved.preconditions?.ifGenerationMatch == 100)
    #expect(resolved.customerEncryptionKey == defaultCsek)
    #expect(resolved.range == ReadObjectRange(prefix: 512))
    #expect(resolved.enableDecompressiveTranscoding == false)
    #expect(resolved.checksums == .off)
    #expect(resolved.resumePolicy is NeverResume<ReadObjectDetails>)
    #expect(resolved.backoffPolicy is ExponentialBackoff)
    #expect(resolved.quotaProject == "default-download-quota")
    #expect(resolved.requestOptions.quotaProject == "default-download-quota")
  }

  @Test func readObjectOptionsWithDefaultsOverridesAllProperties() throws {
    let defaultCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x11, count: 32))
    let overrideCsek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x22, count: 32))
    let defaults = ReadObjectOptions().with {
      $0.generation = 100
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 100 }
      $0.customerEncryptionKey = defaultCsek
      $0.range = ReadObjectRange(prefix: 512)
      $0.enableDecompressiveTranscoding = false
      $0.checksums = .off
      $0.resumePolicy = NeverResume<ReadObjectDetails>()
      $0.backoffPolicy = ExponentialBackoff()
      $0.quotaProject = "default-download-quota"
    }

    let options = ReadObjectOptions().with {
      $0.generation = 200
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 200 }
      $0.customerEncryptionKey = overrideCsek
      $0.range = .entire
      $0.enableDecompressiveTranscoding = true
      $0.checksums = .default
      $0.resumePolicy = AlwaysResume<ReadObjectDetails>.unbounded()
      $0.quotaProject = "override-download-quota"
    }

    let resolved = options.withDefaults(defaults)
    #expect(resolved.generation == 200)
    #expect(resolved.preconditions?.ifGenerationMatch == 200)
    #expect(resolved.customerEncryptionKey == overrideCsek)
    #expect(resolved.range == .entire)
    #expect(resolved.enableDecompressiveTranscoding == true)
    #expect(resolved.checksums == .default)
    #expect(resolved.resumePolicy is AlwaysResume<ReadObjectDetails>)
    #expect(resolved.backoffPolicy is ExponentialBackoff)
    #expect(resolved.quotaProject == "override-download-quota")
    #expect(resolved.requestOptions.quotaProject == "override-download-quota")
  }
}
