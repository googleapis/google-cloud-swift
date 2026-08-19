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
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import Testing

@Suite struct DownloadChecksumTests {
  private func makeClient(registry: MockRegistry) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    return try StorageClient(options, mock: registry)
  }

  @Test func crc32cSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "crc-test.txt"
    let payload = Data("Checksum verification test payload for CRC32C".utf8)

    let computedCrc = _CRC32C.compute(payload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "123",
          "x-goog-hash": "crc32c=\(crcBase64)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)
  }

  @Test func crc32cMismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "crc-mismatch.txt"
    let payload = Data("Checksum verification test payload for CRC32C".utf8)

    let computedCrc = _CRC32C.compute(payload)
    let actualCrcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) {
      Data($0).base64EncodedString()
    }
    let invalidExpectedCrc = "invalid_crc_base64"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "123",
          "x-goog-hash": "crc32c=\(invalidExpectedCrc)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    do {
      for try await _ in result.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: invalidExpectedCrc,
            actual: actualCrcBase64,
            algorithm: "crc32c"
          )
      )
    }
  }

  @Test func md5Success() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "md5-test.txt"
    let payload = Data("Checksum verification test payload for MD5".utf8)

    let md5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "123",
          "x-goog-hash": "md5=\(md5Base64)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)
  }

  @Test func md5Mismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "md5-mismatch.txt"
    let payload = Data("Checksum verification test payload for MD5".utf8)

    let actualMd5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()
    let invalidExpectedMd5 = "invalid_md5_base64"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "123",
          "x-goog-hash": "md5=\(invalidExpectedMd5)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    do {
      for try await _ in result.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: invalidExpectedMd5,
            actual: actualMd5Base64,
            algorithm: "md5"
          )
      )
    }
  }

  @Test func contentMD5Header() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "content-md5.txt"
    let payload = Data("Testing Content-MD5 header verification".utf8)

    let actualMd5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "Content-MD5": actualMd5Base64,
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)

    // Now test Content-MD5 mismatch
    let mismatchUrl = registry.url("/storage/v1/b/\(bucket)/o/mismatch.txt?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "Content-MD5": "wrong_content_md5",
        ]
      ),
      for: mismatchUrl
    )
    let mismatchResult = client.readObject(from: bucket, object: "mismatch.txt", options: options)
    do {
      for try await _ in mismatchResult.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: "wrong_content_md5",
            actual: actualMd5Base64,
            algorithm: "md5"
          )
      )
    }
  }

  @Test func dualChecksums() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "both-hashes.txt"
    let payload = Data("Dual hash verification test payload".utf8)

    let computedCrc = _CRC32C.compute(payload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }
    let md5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-hash": "crc32c=\(crcBase64), md5=\(md5Base64)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)

    // Test dual validation where MD5 fails
    let md5FailUrl = registry.url("/storage/v1/b/\(bucket)/o/md5-fail.txt?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-hash": "crc32c=\(crcBase64), md5=wrong_md5",
        ]
      ),
      for: md5FailUrl
    )
    let md5FailResult = client.readObject(from: bucket, object: "md5-fail.txt", options: options)
    do {
      for try await _ in md5FailResult.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: "wrong_md5",
            actual: md5Base64,
            algorithm: "md5"
          )
      )
    }
  }

  @Test func userProvidedCRC32C() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "user-crc.txt"
    let payload = Data("User provided CRC32C test payload".utf8)

    let computedCrc = _CRC32C.compute(payload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: ["Content-Length": String(payload.count)]
      ),
      for: downloadUrl
    )
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: ["Content-Length": String(payload.count)]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: .value(crcBase64), md5: nil)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)

    // User provided wrong value throws mismatch
    let wrongOptions = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: "wrong_crc_value", md5: nil)
    }
    let wrongResult = client.readObject(from: bucket, object: objectName, options: wrongOptions)
    do {
      for try await _ in wrongResult.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: "wrong_crc_value",
            actual: crcBase64,
            algorithm: "crc32c"
          )
      )
    }
  }

  @Test func userProvidedCRC32CUInt32() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "user-uint32-crc.txt"
    let payload = Data("Hello, World!".utf8)  // CRC32C: 0x4D551068 -> "TVUQaA=="

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: ["Content-Length": String(payload.count)]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: 0x4D55_1068, md5: nil)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)
  }

  @Test func userProvidedMD5() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "user-md5.txt"
    let payload = Data("User provided MD5 test payload".utf8)

    let md5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: ["Content-Length": String(payload.count)]
      ),
      for: downloadUrl
    )
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: ["Content-Length": String(payload.count)]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: .value(md5Base64))
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)

    // Wrong MD5 throws mismatch
    let wrongOptions = ReadObjectOptions().with {
      $0.checksums = ChecksumOptions(crc32c: nil, md5: "wrong_md5_value")
    }
    let wrongResult = client.readObject(from: bucket, object: objectName, options: wrongOptions)
    do {
      for try await _ in wrongResult.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: "wrong_md5_value",
            actual: md5Base64,
            algorithm: "md5"
          )
      )
    }
  }

  @Test func checksumsNone() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "none-validation.txt"
    let payload = Data("No checksum verification payload".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-hash": "crc32c=bad_crc, md5=bad_md5",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.checksums = .none
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)
  }

  @Test func rangedReadSkipsAuto() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "ranged-skip.txt"
    let fullPayload = Data("0123456789ABCDEF0123456789ABCDEF".utf8)
    let rangePayload = Data("0123456789".utf8)

    let fullCrc = _CRC32C.compute(fullPayload)
    let fullCrcBase64 = withUnsafeBytes(of: fullCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 0-9/\(fullPayload.count)",
          "Content-Length": "10",
          "x-goog-hash": "crc32c=\(fullCrcBase64)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .bounded(start: 0, end: 9)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == rangePayload)
  }

  @Test func rangedReadWithUserCRC() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "ranged-user-crc.txt"
    let fullPayload = Data("0123456789ABCDEF0123456789ABCDEF".utf8)
    let rangePayload = Data("0123456789".utf8)

    let rangeCrc = _CRC32C.compute(rangePayload)
    let rangeCrcBase64 = withUnsafeBytes(of: rangeCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 0-9/\(fullPayload.count)",
          "Content-Length": "10",
        ]
      ),
      for: downloadUrl
    )
    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 0-9/\(fullPayload.count)",
          "Content-Length": "10",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .bounded(start: 0, end: 9)
      $0.checksums = ChecksumOptions(crc32c: .value(rangeCrcBase64), md5: nil)
    }
    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == rangePayload)

    // User provided wrong CRC for range throws mismatch
    let wrongOptions = ReadObjectOptions().with {
      $0.range = .bounded(start: 0, end: 9)
      $0.checksums = ChecksumOptions(crc32c: "wrong_range_crc", md5: nil)
    }
    let wrongResult = client.readObject(from: bucket, object: objectName, options: wrongOptions)
    do {
      for try await _ in wrongResult.body {}
      Issue.record("Expected DownloadError.checksumMismatch to be thrown")
    } catch let error as DownloadError {
      #expect(
        error
          == DownloadError.checksumMismatch(
            expected: "wrong_range_crc",
            actual: rangeCrcBase64,
            algorithm: "crc32c"
          )
      )
    }
  }

  @Test func transcodingSkipsAuto() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "transcoded.txt"
    let uncompressedPayload = Data("Uncompressed transcoded text from GCS".utf8)
    let storedCompressedLength: UInt64 = 25

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: uncompressedPayload,
        headers: [
          "Content-Length": String(uncompressedPayload.count),
          "x-goog-stored-content-length": String(storedCompressedLength),
          "x-goog-hash": "crc32c=stored_compressed_crc==",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == uncompressedPayload)
  }

  @Test func resumeCalculatesFullChecksum() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "resume-checksum.bin"
    let chunk1 = Data("First half of streaming payload. ".utf8)
    let chunk2 = Data("Second half after recovery.".utf8)
    let fullPayload = chunk1 + chunk2

    let computedCrc = _CRC32C.compute(fullPayload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=999")

    // Attempt 1: Yields chunk1 then fails with MockNetworkError
    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": String(fullPayload.count),
          "x-goog-generation": "999",
          "x-goog-hash": "crc32c=\(crcBase64)",
        ]
      ),
      for: initialUrl
    )

    // Attempt 2 (Resume from byte chunk1.count): Yields chunk2
    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk2],
        headers: [
          "Content-Range": "bytes \(chunk1.count)-\(fullPayload.count - 1)/\(fullPayload.count)",
          "Content-Length": String(chunk2.count),
          "x-goog-generation": "999",
          "x-goog-hash": "crc32c=\(crcBase64)",
        ]
      ),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == fullPayload)
  }

  @Test func emptyPayloadChecksum() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "empty-object.txt"
    let payload = Data()

    let computedCrc = _CRC32C.compute(payload)  // 0 -> "AAAAAA=="
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": "0",
          "x-goog-generation": "1",
          "x-goog-hash": "crc32c=\(crcBase64)",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(receivedData == payload)
  }
}
