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
// See the License for theing specific language governing permissions and
// limitations under the License.

import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct ChecksumTests {
  @Test func testChecksummedSourceCRC32C() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    var checksummedSource = ChecksummedSource(source: source, validation: .crc32c)

    // Read first chunk
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1 != nil)
    #expect(chunk1!.data == data1)
    #expect(chunk1!.isLast == false)
    #expect(chunk1!.checksum == nil)

    // Read second chunk
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2 != nil)
    #expect(chunk2!.data == data2)
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum != nil)

    // Expected checksum for "Hello, World!"
    #expect(chunk2!.checksum == "crc32c=TVUQaA==")
  }

  @Test func testChecksummedSourceMD5() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    var checksummedSource = ChecksummedSource(source: source, validation: .md5)

    // Read first chunk
    let chunk1 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk1 != nil)
    #expect(chunk1!.data == data1)
    #expect(chunk1!.isLast == false)
    #expect(chunk1!.checksum == nil)

    // Read second chunk
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)
    #expect(chunk2 != nil)
    #expect(chunk2!.data == data2)
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum != nil)

    // Expected checksum for "Hello, World!"
    #expect(chunk2!.checksum == "md5=ZajifYh5KDgxtmS9i38K1A==")
  }

  @Test func testParseChecksumMismatchCRC32C() throws {
    let message = "Provided CRC32C \"n03x6A==\" doesn't match calculated CRC32C \"AAAAAA==\""
    let match = StorageClient.parseChecksumMismatch(message)
    #expect(match != nil)
    #expect(match!.local == "crc32c=n03x6A==")
    #expect(match!.server == "crc32c=AAAAAA==")
  }

  @Test func testParseChecksumMismatchMD5() throws {
    let message = "Provided MD5 \"wXyZ123...\" doesn't match calculated MD5 \"AAAAAA...\""
    let match = StorageClient.parseChecksumMismatch(message)
    #expect(match != nil)
    #expect(match!.local == "md5=wXyZ123...")
    #expect(match!.server == "md5=AAAAAA...")
  }

  @Test func testSimpleUploadChecksumMismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data("Small payload".utf8)
    let source = BytesSource(data: data)

    let uploadUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=multipart&name=\(objectName)")

    let errorMessage =
      "Provided CRC32C \"invalid_crc\" doesn't match calculated CRC32C \"valid_crc\""
    registry.register(
      response: .success(
        statusCode: 400, data: Data(errorMessage.utf8),
        headers: nil),
      for: uploadUrl)

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
    let uploadOptions = UploadOptions(validation: .crc32c)
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    do {
      _ = try await task.value
      Issue.record("Expected upload to fail with checksum mismatch")
    } catch UploadError.checksumMismatch(let local, let server) {
      #expect(local == "crc32c=invalid_crc")
      #expect(server == "crc32c=valid_crc")
    }
  }

  @Test func testResumableUploadChecksumMismatch() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB to trigger resumable upload
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let errorMessage = "Provided MD5 \"invalid_md5\" doesn't match calculated MD5 \"valid_md5\""

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 400, data: Data(errorMessage.utf8),
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
    let uploadOptions = UploadOptions(validation: .md5)
    let task = client.upload(source, to: bucket, as: objectName, options: uploadOptions)

    do {
      _ = try await task.value
      Issue.record("Expected upload to fail with checksum mismatch")
    } catch UploadError.checksumMismatch(let local, let server) {
      #expect(local == "md5=invalid_md5")
      #expect(server == "md5=valid_md5")
    }
  }

  @Test func testChecksummedSourceMultipleAuto() async throws {
    let data1 = Data("Hello, ".utf8)
    let data2 = Data("World!".utf8)
    let combinedData = data1 + data2

    let source = BytesSource(data: combinedData)
    let checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    _ = try await checksummedSource.readChunk(maxBytes: 7)
    let chunk2 = try await checksummedSource.readChunk(maxBytes: 7)

    #expect(chunk2 != nil)
    #expect(chunk2!.isLast == true)
    #expect(chunk2!.checksum == "crc32c=TVUQaA==, md5=ZajifYh5KDgxtmS9i38K1A==")
  }

  @Test func testChecksummedSourceUserProvidedValues() async throws {
    let source = BytesSource(data: Data("Some data".utf8))
    let checksums = ChecksumOptions(crc32c: "PRE_CRC", md5: "PRE_MD5")
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    let chunk = try await checksummedSource.readChunk(maxBytes: 100)

    #expect(chunk != nil)
    #expect(chunk!.isLast == true)
    #expect(chunk!.checksum == "crc32c=PRE_CRC, md5=PRE_MD5")
  }

  @Test func testChecksummedSourceMixedAutoAndUserProvided() async throws {
    let data = Data("Hello, World!".utf8)
    let source = BytesSource(data: data)
    let checksums = ChecksumOptions(crc32c: .auto, md5: "CUSTOM_MD5")
    var checksummedSource = ChecksummedSource(source: source, options: checksums)

    let chunk = try await checksummedSource.readChunk(maxBytes: 100)

    #expect(chunk != nil)
    #expect(chunk!.isLast == true)
    #expect(chunk!.checksum == "crc32c=TVUQaA==, md5=CUSTOM_MD5")
  }
}
