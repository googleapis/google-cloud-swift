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

  private func makeClient(
    registry: MockRegistry,
    retryPolicy: (any RetryPolicy)? = nil,
    downloadOptions: ReadObjectOptions? = nil
  ) throws -> StorageClient {
    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0.credentials = try! Credentials(configuration: .anonymous)
        if let retryPolicy {
          $0.retryPolicy = retryPolicy
        }
      }
      if let downloadOptions {
        $0.download = downloadOptions
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
    let computedCrc = _CRC32C.compute(payload)
    let crcBase64 = withUnsafeBytes(of: computedCrc.bigEndian) { Data($0).base64EncodedString() }
    let md5Base64 = Data(Insecure.MD5.hash(data: payload)).base64EncodedString()

    let headers = [
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": String(payload.count),
      "x-goog-generation": "17123456789",
      "x-goog-metageneration": "3",
      "ETag": "\"CPv1234\"",
      "x-goog-hash": "crc32c=\(crcBase64), md5=\(md5Base64)",
      "x-goog-storage-class": "STANDARD",
      "Last-Modified": "Fri, 07 Aug 2026 01:00:00 GMT",
    ]

    registry.register(
      response: .success(statusCode: 200, data: payload, headers: headers),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.bucket == "projects/_/buckets/\(bucket)")
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(payload.count))
    #expect(metadata.generation == 17123456789)
    #expect(metadata.metageneration == 3)
    #expect(metadata.etag == "\"CPv1234\"")
    #expect(metadata.crc32c == crcBase64)
    #expect(metadata.md5Hash == md5Base64)
    #expect(metadata.contentType == "text/plain; charset=utf-8")
    #expect(metadata.storageClass == "STANDARD")
    #expect(metadata.updated != nil)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.bucket == "projects/_/buckets/\(bucket)")
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(payload.count))
    #expect(metadata.generation == 42)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(lastReq?.value(forHTTPHeaderField: "x-goog-encryption-key") == csek.keyBase64)
    #expect(
      lastReq?.value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == csek.keyHashBase64)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.size == 4)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)

    for (header, expectedValue) in expectedHeaders {
      #expect(lastReq?.value(forHTTPHeaderField: header) == expectedValue)
    }

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
      try await client.readObject(from: bucket, object: objectName, options: options).metadata
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
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.bucket == "projects/_/buckets/\(bucket)")
    #expect(metadata.object == objectName)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
      try await client.readObject(from: bucket, object: objectName).metadata
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.size == 50)
    #expect(metadata.generation == 123)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=10-")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=0-19")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=-15")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
      $0.range = .bounded(10...29)
    }

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata
    #expect(metadata.size == 50)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq?.value(forHTTPHeaderField: "Range") == "bytes=10-29")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
      options: ReadObjectOptions().with { $0.range = ReadObjectRange(10...29) }
    ).metadata
    #expect(
      registry.lastRequest(for: downloadUrl)?.value(forHTTPHeaderField: "Range") == "bytes=10-29")
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

    let prefixResult = client.readObject(
      from: bucket,
      object: prefixObject,
      options: ReadObjectOptions().with { $0.range = .prefix(0) }
    )
    let prefixMeta = try await prefixResult.metadata
    #expect(prefixMeta.size == 50)
    #expect(prefixMeta.generation == 123)
    #expect(
      registry.lastRequest(for: prefixUrl)?.value(forHTTPHeaderField: "Range") == "bytes=0-0")

    var prefixData = Data()
    for try await chunk in prefixResult.body {
      prefixData.append(contentsOf: chunk)
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

    let suffixResult = client.readObject(
      from: bucket,
      object: suffixObject,
      options: ReadObjectOptions().with { $0.range = .suffix(0) }
    )
    let suffixMeta = try await suffixResult.metadata
    #expect(suffixMeta.size == 50)
    #expect(suffixMeta.generation == 123)
    #expect(
      registry.lastRequest(for: suffixUrl)?.value(forHTTPHeaderField: "Range") == "bytes=-0")

    var suffixData = Data()
    for try await chunk in suffixResult.body {
      suffixData.append(contentsOf: chunk)
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
      ).metadata
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata

    #expect(metadata.bucket == "projects/_/buckets/\(bucket)")
    #expect(metadata.object == objectName)
    #expect(metadata.contentEncoding == "gzip")
    #expect(metadata.size == UInt64(payload.count))

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "Accept-Encoding") == "gzip")

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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

    let result = client.readObject(from: bucket, object: objectName, options: options)
    let metadata = try await result.metadata

    #expect(metadata.bucket == "projects/_/buckets/\(bucket)")
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(payload.count))

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
    #expect(lastReq?.value(forHTTPHeaderField: "Accept-Encoding") == nil)

    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
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
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.size == UInt64(fullPayload.count))
    #expect(metadata.generation == 999)

    var receivedChunks: [Data] = []
    for try await chunk in result.body {
      receivedChunks.append(chunk.data)
    }

    #expect(receivedChunks.count == 3)
    #expect(receivedChunks[0] == chunk1)
    #expect(receivedChunks[1] == chunk2)
    #expect(receivedChunks[2] == chunk3)
    #expect(receivedChunks.reduce(Data(), +) == fullPayload)
  }

  @Test func downloadObjectTransientFailureRetriesAndSucceeds() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-retry.txt"
    let payload = Data("Download retry success payload".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(statusCode: 503, data: Data("Service Unavailable".utf8), headers: nil),
      for: downloadUrl
    )
    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "100",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(
      registry: registry, retryPolicy: BaseRetryPolicy().withAttemptLimit(3))
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.generation == 100)
    var downloaded = Data()
    for try await chunk in result.body {
      downloaded.append(contentsOf: chunk)
    }
    #expect(downloaded == payload)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
  }

  @Test func downloadObjectTransientFailureWithNeverResumeFails() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-never-resume.txt"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(statusCode: 503, data: Data("Service Unavailable".utf8), headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(
      registry: registry,
      downloadOptions: ReadObjectOptions().with { $0.resumePolicy = NeverResume<DownloadDetails>() }
    )

    let err = await expectError(DownloadError.self) {
      try await client.readObject(from: bucket, object: objectName).metadata
    }
    #expect(err != nil)

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  @Test func downloadObjectWithCustomReadObjectOptionsResumePolicyOverridesClient() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-override-resume.txt"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(statusCode: 503, data: Data("Service Unavailable".utf8), headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.resumePolicy = NeverResume<DownloadDetails>()
    }

    let err = await expectError(DownloadError.self) {
      try await client.readObject(from: bucket, object: objectName, options: options).metadata
    }
    #expect(err != nil)

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  @Test func downloadObjectWithClientDownloadOptionsResumePolicyOverridesDefault() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-client-override.txt"

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(statusCode: 503, data: Data("Service Unavailable".utf8), headers: nil),
      for: downloadUrl
    )

    let client = try makeClient(
      registry: registry,
      downloadOptions: ReadObjectOptions().with { $0.resumePolicy = NeverResume<DownloadDetails>() }
    )

    let err = await expectError(DownloadError.self) {
      try await client.readObject(from: bucket, object: objectName).metadata
    }
    #expect(err != nil)

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  @Test func downloadObjectStreamingTransientFailureResumesFromLatestByte() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "streaming-resume.bin"
    let chunk1 = Data("FirstPart-".utf8)
    let chunk2 = Data("SecondPart".utf8)
    let fullPayload = chunk1 + chunk2

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=888")

    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": String(fullPayload.count),
          "x-goog-generation": "888",
        ]
      ),
      for: initialUrl
    )

    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk2],
        headers: [
          "Content-Range": "bytes \(chunk1.count)-\(fullPayload.count - 1)/\(fullPayload.count)",
          "Content-Length": String(chunk2.count),
          "x-goog-generation": "888",
        ]
      ),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.size == UInt64(fullPayload.count))
    #expect(metadata.generation == 888)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }

    #expect(receivedData == fullPayload)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[0].value(forHTTPHeaderField: "Range") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Range") == "bytes=\(chunk1.count)-")
  }

  @Test func downloadObjectStreamingMultipleTransientFailuresResumesAndRecovers() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "multi-resume.bin"
    let chunk1 = Data("1111111111".utf8)
    let chunk2 = Data("2222222222".utf8)
    let chunk3 = Data("3333333333".utf8)
    let fullPayload = chunk1 + chunk2 + chunk3

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=777")

    // Attempt 1: Yields chunk1, then network fails
    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": String(fullPayload.count),
          "x-goog-generation": "777",
        ]
      ),
      for: initialUrl
    )

    // Attempt 2 (Resume at 10): Yields chunk2, then network fails again
    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk2],
        error: MockNetworkError(),
        headers: [
          "Content-Range": "bytes 10-\(fullPayload.count - 1)/\(fullPayload.count)",
          "Content-Length": String(chunk2.count + chunk3.count),
          "x-goog-generation": "777",
        ]
      ),
      for: resumeUrl
    )

    // Attempt 3 (Resume at 20): Yields chunk3 and finishes cleanly
    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk3],
        headers: [
          "Content-Range": "bytes 20-\(fullPayload.count - 1)/\(fullPayload.count)",
          "Content-Length": String(chunk3.count),
          "x-goog-generation": "777",
        ]
      ),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }

    #expect(receivedData == fullPayload)

    let requests = registry.recordedRequests()
    #expect(requests.count == 3)
    #expect(requests[0].value(forHTTPHeaderField: "Range") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Range") == "bytes=10-")
    #expect(requests[2].value(forHTTPHeaderField: "Range") == "bytes=20-")
  }

  @Test func downloadObjectStreamingWithBoundedRangeResumesFromOffset() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "bounded-resume.bin"
    let chunk1 = Data("0123456789".utf8)
    let chunk2 = Data("abcdefghij".utf8)
    let expectedPayload = chunk1 + chunk2

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=555")

    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Range": "bytes 10-29/100",
          "Content-Length": "20",
          "x-goog-generation": "555",
        ]
      ),
      for: initialUrl
    )

    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk2],
        headers: [
          "Content-Range": "bytes 20-29/100",
          "Content-Length": "10",
          "x-goog-generation": "555",
        ]
      ),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.range = .bounded(10...29)
    }

    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }

    #expect(receivedData == expectedPayload)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[0].value(forHTTPHeaderField: "Range") == "bytes=10-29")
    #expect(requests[1].value(forHTTPHeaderField: "Range") == "bytes=20-29")
  }

  @Test func downloadObjectStreamingWithNeverResumeThrowsOnStreamInterruption() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "no-resume.bin"
    let chunk1 = Data("FirstPart-".utf8)

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": "100",
          "x-goog-generation": "333",
        ]
      ),
      for: initialUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.resumePolicy = NeverResume<DownloadDetails>()
    }

    let result = client.readObject(from: bucket, object: objectName, options: options)

    do {
      for try await _ in result.body {}
      Issue.record("Expected error to be thrown when resumePolicy is NeverResume")
    } catch DownloadError.resumeFailed(let bytesReceived, _) {
      #expect(bytesReceived == UInt64(chunk1.count))
    } catch {
      Issue.record("Expected DownloadError.resumeFailed, but got \(error)")
    }

    let requests = registry.recordedRequests()
    #expect(requests.count == 1)
  }

  @Test func downloadObjectStreamingResumePermanentErrorThrows() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "resume-404.bin"
    let chunk1 = Data("InitialData".utf8)

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=222")

    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": "50",
          "x-goog-generation": "222",
        ]
      ),
      for: initialUrl
    )

    registry.register(
      response: .success(statusCode: 404, data: Data("Object deleted".utf8), headers: nil),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    do {
      for try await _ in result.body {}
      Issue.record("Expected error when resume fails with 404")
    } catch DownloadError.unexpectedServerResponse(let statusCode, let message) {
      #expect(statusCode == 404)
      #expect(message == "Object deleted")
    } catch {
      Issue.record("Expected unexpectedServerResponse 404, got \(error)")
    }
  }

  @Test func downloadObjectStreamingWithCustomerSuppliedEncryptionKeyPreservesHeadersOnResume()
    async throws
  {
    let registry = MockRegistry.create()
    let bucket = "csek-bucket"
    let objectName = "csek-resume.bin"
    let chunk1 = Data("encrypted-part1".utf8)
    let chunk2 = Data("encrypted-part2".utf8)
    let fullPayload = chunk1 + chunk2
    let csek = Self.sampleCsek

    let initialUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")
    let resumeUrl = registry.url(
      "/storage/v1/b/\(bucket)/o/\(objectName)?alt=media&generation=111")

    registry.register(
      response: .stream(
        statusCode: 200,
        chunks: [chunk1],
        error: MockNetworkError(),
        headers: [
          "Content-Length": String(fullPayload.count),
          "x-goog-generation": "111",
        ]
      ),
      for: initialUrl
    )

    registry.register(
      response: .stream(
        statusCode: 206,
        chunks: [chunk2],
        headers: [
          "Content-Range": "bytes \(chunk1.count)-\(fullPayload.count - 1)/\(fullPayload.count)",
          "Content-Length": String(chunk2.count),
          "x-goog-generation": "111",
        ]
      ),
      for: resumeUrl
    )

    let client = try makeClient(registry: registry)
    let options = ReadObjectOptions().with {
      $0.customerEncryptionKey = csek
    }

    let result = client.readObject(from: bucket, object: objectName, options: options)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }

    #expect(receivedData == fullPayload)

    let requests = registry.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests[1].value(forHTTPHeaderField: "x-goog-encryption-algorithm") == "AES256")
    #expect(requests[1].value(forHTTPHeaderField: "x-goog-encryption-key") == csek.keyBase64)
    #expect(
      requests[1].value(forHTTPHeaderField: "x-goog-encryption-key-sha256") == csek.keyHashBase64)
  }

  @Test func downloadObjectDeferredExecutionOnlyAwaitsMetadata() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "meta-only.txt"
    let payload = Data("Only read metadata".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "999",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.size == UInt64(payload.count))
    #expect(metadata.generation == 999)

    // Result body was never consumed, download finishes or cancels cleanly
    result.cancel()
  }

  @Test func downloadObjectDeferredExecutionOnlyConsumesBody() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "body-only.txt"
    let payload = Data("Direct stream consumption without metadata read".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(bucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "x-goog-generation": "888",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucket, object: objectName)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }

    #expect(receivedData == payload)
  }

  /// Tests downloading an object when bucket is specified as a canonical resource name (e.g. `projects/_/buckets/my-bucket`).
  @Test func downloadObjectWithBucketResourceName() async throws {
    let registry = MockRegistry.create()
    let rawBucket = "download-resource-bucket"
    let bucketResource = "projects/_/buckets/\(rawBucket)"
    let objectName = "file.txt"
    let payload = Data("Resource Name Download Content".utf8)

    let downloadUrl = registry.url("/storage/v1/b/\(rawBucket)/o/\(objectName)?alt=media")

    registry.register(
      response: .success(
        statusCode: 200,
        data: payload,
        headers: [
          "Content-Length": String(payload.count),
          "Content-Type": "text/plain",
          "x-goog-generation": "999",
        ]
      ),
      for: downloadUrl
    )

    let client = try makeClient(registry: registry)
    let result = client.readObject(from: bucketResource, object: objectName)
    let metadata = try await result.metadata

    #expect(metadata.bucket == bucketResource)
    #expect(metadata.object == objectName)
    #expect(metadata.size == UInt64(payload.count))
    #expect(metadata.generation == 999)

    var receivedData = Data()
    for try await chunk in result.body {
      receivedData.append(contentsOf: chunk)
    }
    #expect(receivedData == payload)

    let lastReq = registry.lastRequest(for: downloadUrl)
    #expect(lastReq != nil)
  }
}
