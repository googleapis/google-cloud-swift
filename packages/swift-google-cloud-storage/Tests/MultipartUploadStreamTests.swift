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
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import NIOCore
import Testing

@Suite struct MultipartUploadStreamTests {
  /// Tests MultipartUploadStream framing and content length matching.
  @Test func multipartUploadStreamFraming() async throws {
    let boundary = "TestBoundary123"
    let metadataJson = Data("{\"name\":\"test.txt\"}".utf8)
    let payload = Data("Hello, World!".utf8)
    let source = BytesSource(data: payload)

    let stream = MultipartUploadStream(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "text/plain",
      totalSize: Int64(payload.count),
      chunkSize: 4
    )

    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }

    let expectedPreamble =
      "--TestBoundary123\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{\"name\":\"test.txt\"}\r\n--TestBoundary123\r\nContent-Type: text/plain\r\n\r\n"
    let expectedEpilogue = "\r\n--TestBoundary123--\r\n"
    let expectedFullString = expectedPreamble + "Hello, World!" + expectedEpilogue

    #expect(collected.readableBytes == stream.bodyLength)
    #expect(collected.readableBytes == expectedFullString.utf8.count)

    let actualString = collected.withUnsafeReadableBytes { String(decoding: $0, as: UTF8.self) }
    #expect(actualString == expectedFullString)
  }

  /// Tests MultipartUploadStream.prepare with a SeekableUploadSource and automatic checksums.
  @Test func multipartUploadStreamPrepareSeekable() async throws {
    let boundary = "TestBoundary456"
    let metadataJson = Data("{}".utf8)
    let payload = Data("1234567890".utf8)
    let source = BytesSource(data: payload)

    let prepared = try await MultipartUploadStream.prepare(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "application/octet-stream",
      totalSize: Int64(payload.count),
      options: .default,
      chunkSize: 4
    )
    let stream = prepared.stream
    let checksum = prepared.checksum

    #expect(checksum != nil)
    #expect(checksum?.hasPrefix("crc32c=") == true)

    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(collected.readableBytes == stream.bodyLength)
  }

  /// Tests MultipartUploadStream.prepare with a non-seekable UploadSource and automatic checksums.
  @Test func multipartUploadStreamPrepareNonSeekable() async throws {
    let boundary = "TestBoundary789"
    let metadataJson = Data("{}".utf8)
    let payload = Data("streaming non-seekable payload".utf8)
    let asyncStream = AsyncStream<Data> { continuation in
      continuation.yield(payload)
      continuation.finish()
    }
    let source = StreamSource(sequence: asyncStream, totalSize: Int64(payload.count))

    let prepared = try await MultipartUploadStream.prepare(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "text/plain",
      totalSize: Int64(payload.count),
      options: .default,
      chunkSize: 8
    )
    let stream = prepared.stream
    let checksum = prepared.checksum

    #expect(checksum != nil)
    #expect(checksum?.hasPrefix("crc32c=") == true)

    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(collected.readableBytes == stream.bodyLength)
  }

  /// Tests MultipartUploadStream.prepare when checksum calculation is disabled.
  @Test func multipartUploadStreamPrepareNone() async throws {
    let boundary = "TestBoundaryNone"
    let metadataJson = Data("{}".utf8)
    let payload = Data("no checksum calculation".utf8)
    let source = BytesSource(data: payload)

    let prepared = try await MultipartUploadStream.prepare(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "text/plain",
      totalSize: Int64(payload.count),
      options: .none,
      chunkSize: 4
    )
    let stream = prepared.stream
    let checksum = prepared.checksum

    #expect(checksum == nil)

    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(collected.readableBytes == stream.bodyLength)
  }

  /// Tests that MultipartUploadStream throws when the source returns fewer bytes than totalSize.
  @Test func multipartUploadStreamFewerBytesError() async throws {
    let boundary = "TestBoundaryErr"
    let metadataJson = Data("{}".utf8)
    let source = MockUploadSource(data: Data([1, 2, 3]), totalSize: 100)

    let stream = MultipartUploadStream(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "application/octet-stream",
      totalSize: 100,
      chunkSize: 10
    )

    let error = await expectUploadError {
      for try await _ in stream {}
      return nil
    }
    if case .internalError(let message) = error {
      #expect(message == "Failed to read data from source")
    } else {
      Issue.record("Expected .internalError, got \(String(describing: error))")
    }
  }
}
