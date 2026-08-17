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

@Suite struct DownloadTests {
  private static func sampleKey() -> CustomerEncryptionKeyOptions {
    let keyData = Data(repeating: 0x42, count: 32)
    return try! CustomerEncryptionKeyOptions(key: keyData)
  }

  private static let sampleCsek = sampleKey()

  private func makeClient(registry: MockRegistry) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
      }
    }
    return try StorageClient(options, mock: registry)
  }

  @Test func downloadObjectSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "my-object.txt"
    let payload = Data("Hello, Cloud Storage download!".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    let headers = [
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": String(payload.count),
      "x-goog-generation": "17123456789",
      "x-goog-metageneration": "3",
      "ETag": "\"CPv1234\"",
      "x-goog-hash": "crc32c=AdiAvw==, md5=N1YvABC==",
      "x-goog-storage-class": "STANDARD",
      "Last-Modified": "Fri, 07 Aug 2026 01:00:00 GMT",
    ]

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: headers),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = try await client.readObject(from: bucket, object: objectName)

    #expect(result.metadata.bucket == bucket)
    #expect(result.metadata.object == objectName)
    #expect(result.metadata.size == UInt64(payload.count))
    #expect(result.metadata.generation == 17123456789)
    #expect(result.metadata.metageneration == 3)
    #expect(result.metadata.etag == "\"CPv1234\"")
    #expect(result.metadata.crc32c == "AdiAvw==")
    #expect(result.metadata.md5Hash == "N1YvABC==")
    #expect(result.metadata.contentType == "text/plain; charset=utf-8")
    #expect(result.metadata.storageClass == "STANDARD")
    #expect(result.metadata.updated != nil)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test func downloadObjectWithCustomerSuppliedEncryptionKey() async throws {
    let registry = MockRegistry.create()
    let bucket = "csek-bucket"
    let objectName = "secret-file.dat"
    let rawKey = Data((0..<32).map { UInt8($0) })
    let csek = try CustomerEncryptionKeyOptions(key: rawKey)
    let payload = Data("encrypted secret content".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "Content-Type": "application/octet-stream",
          "x-goog-generation": "42",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.customerEncryptionKey = csek
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.bucket == bucket)
    #expect(result.metadata.object == objectName)
    #expect(result.metadata.size == UInt64(payload.count))
    #expect(result.metadata.generation == 42)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(lastReq?.value(forHTTPHeaderField: "x-goog-encryption-key") == csek.keyBase64)
    #expect(
      lastReq?.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == csek.keyHashBase64)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test(arguments: [
    (
      ReadObjectOptions().with { $0.generation = 999 },
      "generation=999",
      [:] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 888 }
      },
      "ifGenerationMatch=888",
      [:] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.preconditions = StoragePreconditions().with { $0.ifGenerationNotMatch = 777 }
      },
      "ifGenerationNotMatch=777",
      [:] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.preconditions = StoragePreconditions().with { $0.ifMetagenerationMatch = 666 }
      },
      "ifMetagenerationMatch=666",
      [:] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.preconditions = StoragePreconditions().with { $0.ifMetagenerationNotMatch = 555 }
      },
      "ifMetagenerationNotMatch=555",
      [:] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.generation = 999
        $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 888 }
        $0.customerEncryptionKey = sampleCsek
      },
      "generation=999&ifGenerationMatch=888",
      [
        "x-goog-encryption-algorithm": "AES256",
        "x-goog-encryption-key": sampleCsek.keyBase64,
        "x-goog-encryption-key-sha256": sampleCsek.keyHashBase64,
      ] as [String: String]
    ),
    (
      ReadObjectOptions().with {
        $0.generation = 12345
        $0.preconditions = StoragePreconditions().with {
          $0.ifGenerationMatch = 12345
          $0.ifGenerationNotMatch = 11111
          $0.ifMetagenerationMatch = 2
          $0.ifMetagenerationNotMatch = 1
        }
      },
      "generation=12345&ifGenerationMatch=12345&ifGenerationNotMatch=11111&ifMetagenerationMatch=2&ifMetagenerationNotMatch=1",
      [:] as [String: String]
    ),
  ])
  func downloadObjectWithOptions(
    options: ReadObjectOptions,
    expectedQuery: String,
    expectedHeaders: [String: String]
  ) async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "encrypted.bin"
    let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])

    let downloadUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&\(expectedQuery)"
    )

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: ["Content-Length": "4"]),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.size == 4)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)

    for (header, expectedValue) in expectedHeaders {
      #expect(lastReq?.value(forHTTPHeaderField: header) == expectedValue)
    }

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test func downloadObjectPreconditionFailed() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "data.bin"

    let downloadUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&ifGenerationMatch=999"
    )

    registry.register(
      response: .success(statusCode: 412, data: Data("Precondition Failed".utf8), headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.preconditions = StoragePreconditions().with { $0.ifGenerationMatch = 999 }
    }

    let err = await expectError(DownloadError.self) {
      try await client.readObject(from: bucket, object: objectName, options: options)
    }

    if case .unexpectedServerResponse(let statusCode, let message) = err {
      #expect(statusCode == 412)
      #expect(message == "Precondition Failed")
    } else {
      Issue.record("Expected unexpectedServerResponse with 412 status code")
    }
  }

  @Test(arguments: [
    ("folder/subfolder/file.json", "folder%2Fsubfolder%2Ffile.json"),
    ("file with spaces.txt", "file%20with%20spaces.txt"),
    ("file&name.txt", "file&name.txt"),
    ("file?name.txt", "file%3Fname.txt"),
    ("file#name.txt", "file%23name.txt"),
    (
      "folder/subfolder/file with & and ?.json",
      "folder%2Fsubfolder%2Ffile%20with%20&%20and%20%3F.json"
    ),
  ])
  func downloadObjectWithSpecialCharactersInPath(
    objectName: String, encodedObjectName: String
  ) async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let payload = Data("{}".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(encodedObjectName)?alt=media")

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = try await client.readObject(from: bucket, object: objectName)

    #expect(result.metadata.bucket == bucket)
    #expect(result.metadata.object == objectName)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test func downloadObjectErrorHandling() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "missing.txt"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(statusCode: 404, data: Data("Object not found".utf8), headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)

    let err = await expectError(DownloadError.self) {
      try await client.readObject(from: bucket, object: objectName)
    }

    if case .unexpectedServerResponse(let statusCode, let message) = err {
      #expect(statusCode == 404)
      #expect(message == "Object not found")
    } else {
      Issue.record("Expected unexpectedServerResponse error")
    }
  }

  @Test func downloadObjectWithRangeFromOffset() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "range-offset.txt"
    let fullPayload = Data((0..<50).map { UInt8($0) })
    let rangePayload = fullPayload.subdata(in: 10..<50)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 10-49/50",
          "Content-Length": String(rangePayload.count),
          "x-goog-generation": "123",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .fromOffset(10)
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.size == 50)
    #expect(result.metadata.generation == 123)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=10-")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == rangePayload)
  }

  @Test func downloadObjectWithRangePrefix() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "range-prefix.txt"
    let fullPayload = Data((0..<50).map { UInt8($0) })
    let rangePayload = fullPayload.subdata(in: 0..<20)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 0-19/50",
          "Content-Length": String(rangePayload.count),
          "x-goog-generation": "124",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .prefix(20)
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=0-19")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == rangePayload)
  }

  @Test func downloadObjectWithRangeSuffix() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "range-suffix.txt"
    let fullPayload = Data((0..<50).map { UInt8($0) })
    let rangePayload = fullPayload.subdata(in: 35..<50)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 35-49/50",
          "Content-Length": String(rangePayload.count),
          "x-goog-generation": "125",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .suffix(15)
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=-15")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == rangePayload)
  }

  @Test func downloadObjectWithRangeBounded() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "range-bounded.txt"
    let fullPayload = Data((0..<50).map { UInt8($0) })
    let rangePayload = fullPayload.subdata(in: 10..<30)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 206,
        data: rangePayload,
        headers: [
          "Content-Range": "bytes 10-29/50",
          "Content-Length": String(rangePayload.count),
          "x-goog-generation": "126",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .bounded(start: 10, end: 29)
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)
    #expect(result.metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=10-29")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == rangePayload)
  }

  @Test func downloadObjectWithClosedRange() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "range-closed.txt"
    let payload = Data("0123456789".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let client = try makeClient(registry: registry)

    registry.register(
      response: .success(
        statusCode: 206,
        data: payload,
        headers: ["Content-Range": "bytes 0-9/10"]
      ),
      for: downloadUrl
    )

    _ = try await client.readObject(
      from: bucket, object: objectName,
      options: ReadObjectOptions().with { $0.range = ReadObjectRange(10...29) })
    #expect(
      registry.lastRequest(for: downloadUrl)?.value(forHTTPHeaderField: "Range") == "bytes=10-29")
  }

  @Test func rangedDownloadInvalidRangeThrows() async throws {
    let registry = MockRegistry.create()
    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .bounded(start: 30, end: 10)
    }

    do {
      _ = try await client.readObject(from: "test-bucket", object: "test.txt", options: options)
      Issue.record("Expected invalidRangeHeader error to be thrown")
    } catch let DownloadError.invalidRangeHeader(msg) {
      #expect(msg.contains("30"))
      #expect(msg.contains("10"))
    } catch {
      Issue.record("Expected invalidRangeHeader, but got \(error)")
    }
  }

  @Test func rangedDownloadZeroCountRanges() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let client = try makeClient(registry: registry)

    // Prefix 0
    let prefixObject = "test-prefix.txt"
    let prefixUrl = registry.url("/storage/v1/b/\(bucket)/o/\(prefixObject)?alt=media")
    registry.register(
      response: .success(
        statusCode: 206,
        data: Data([0x42]),
        headers: [
          "Content-Range": "bytes 0-0/50",
          "x-goog-generation": "123",
        ]
      ),
      for: prefixUrl
    )

    let prefixResult = try await client.readObject(
      from: bucket,
      object: prefixObject,
      options: ReadObjectOptions().with { $0.range = .prefix(0) }
    )
    #expect(prefixResult.metadata.size == 50)
    #expect(prefixResult.metadata.generation == 123)
    #expect(
      registry.lastRequest(for: prefixUrl)?.value(forHTTPHeaderField: "Range") == "bytes=0-0")

    var prefixData = Data()
    for try await chunk in prefixResult.body {
      prefixData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(prefixData.isEmpty)

    // Suffix 0
    let suffixObject = "test-suffix.txt"
    let suffixUrl = registry.url("/storage/v1/b/\(bucket)/o/\(suffixObject)?alt=media")
    registry.register(
      response: .success(
        statusCode: 206,
        data: Data([0x42]),
        headers: [
          "Content-Range": "bytes 0-0/50",
          "x-goog-generation": "123",
        ]
      ),
      for: suffixUrl
    )

    let suffixResult = try await client.readObject(
      from: bucket,
      object: suffixObject,
      options: ReadObjectOptions().with { $0.range = .suffix(0) }
    )
    #expect(suffixResult.metadata.size == 50)
    #expect(suffixResult.metadata.generation == 123)
    #expect(
      registry.lastRequest(for: suffixUrl)?.value(forHTTPHeaderField: "Range") == "bytes=-0")

    var suffixData = Data()
    for try await chunk in suffixResult.body {
      suffixData.append(contentsOf: chunk.readableBytesView)
    }
    #expect(suffixData.isEmpty)

    // 0-byte read on non-existent object throws 404
    let notFoundUrl = registry.url("/storage/v1/b/\(bucket)/o/nonexistent.txt?alt=media")
    registry.register(
      response: .success(statusCode: 404, data: Data("Not Found".utf8), headers: nil),
      for: notFoundUrl
    )
    do {
      _ = try await client.readObject(
        from: bucket,
        object: "nonexistent.txt",
        options: ReadObjectOptions().with { $0.range = .prefix(0) }
      )
      Issue.record("Expected unexpectedServerResponse error to be thrown for 404")
    } catch DownloadError.unexpectedServerResponse(let statusCode, _) {
      #expect(statusCode == 404)
    } catch {
      Issue.record("Expected unexpectedServerResponse, got \(error)")
    }
  }

  @Test func downloadObjectWithDecompressiveTranscodingDisabledSendsAcceptEncodingGzip()
    async throws
  {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "compressed-file.txt.gz"
    let payload = Data([
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

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    let headers = [
      "Content-Type": "text/plain",
      "Content-Encoding": "gzip",
      "Content-Length": String(payload.count),
      "x-goog-generation": "12345",
      "x-goog-metageneration": "1",
    ]

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: headers),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.enableDecompressiveTranscoding = false
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)

    #expect(result.metadata.bucket == bucket)
    #expect(result.metadata.object == objectName)
    #expect(result.metadata.contentEncoding == "gzip")
    #expect(result.metadata.size == UInt64(payload.count))

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "Accept-Encoding") == "gzip")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test func downloadObjectWithDecompressiveTranscodingEnabledDoesNotSendAcceptEncoding()
    async throws
  {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "uncompressed-file.txt"
    let payload = Data("Hello, uncompressed content!".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    let headers = [
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": String(payload.count),
      "x-goog-generation": "12345",
      "x-goog-metageneration": "1",
    ]

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: headers),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.enableDecompressiveTranscoding = true
    }

    let result = try await client.readObject(from: bucket, object: objectName, options: options)

    #expect(result.metadata.bucket == bucket)
    #expect(result.metadata.object == objectName)
    #expect(result.metadata.size == UInt64(payload.count))

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "Accept-Encoding") == nil)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk.readableBytesView)
    }
    #expect(downloaded == payload)
  }

  @Test func downloadObjectStreaming() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "stream-object.bin"
    let chunk1 = Data("Chunk-1-".utf8)
    let chunk2 = Data("Chunk-2-".utf8)
    let chunk3 = Data("Chunk-3".utf8)
    let fullPayload = chunk1 + chunk2 + chunk3
    let computedCrc = _CRC32C.compute(fullPayload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let headers = [
      "Content-Type": "application/octet-stream",
      "Content-Length": String(fullPayload.count),
      "x-goog-generation": "999",
      "x-goog-hash": "crc32c=\(crcBase64)",
    ]

    registry.register(
      response: .stream(statusCode: 200, chunks: [chunk1, chunk2, chunk3], headers: headers),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = try await client.readObject(from: bucket, object: objectName)

    #expect(result.metadata.size == UInt64(fullPayload.count))
    #expect(result.metadata.generation == 999)

    var receivedChunks: [Data] = []
    for try await chunk in result.body {
      receivedChunks.append(Data(buffer: chunk))
    }

    #expect(receivedChunks.count == 3)
    #expect(receivedChunks[0] == chunk1)
    #expect(receivedChunks[1] == chunk2)
    #expect(receivedChunks[2] == chunk3)
    #expect(receivedChunks.reduce(Data(), +) == fullPayload)
  }
}
