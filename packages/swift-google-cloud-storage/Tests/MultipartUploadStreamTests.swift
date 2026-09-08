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
      totalSize: UInt64(payload.count),
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

    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
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
      totalSize: UInt64(payload.count),
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
    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
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
    let source = StreamSource(sequence: asyncStream, totalSize: UInt64(payload.count))

    let prepared = try await MultipartUploadStream.prepare(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "text/plain",
      totalSize: UInt64(payload.count),
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
    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
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
      totalSize: UInt64(payload.count),
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
    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
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

  /// Tests that MultipartUploadStream can be iterated multiple times when using struct-based sources because the stored source is not mutated by iteration.
  @Test func multipartUploadStreamCanBeIteratedMultipleTimes() async throws {
    let boundary = "TestBoundaryMultiIter"
    let metadataJson = Data("{\"name\":\"test.txt\"}".utf8)
    let payload = Data("Testing multiple iterations".utf8)
    let source = BytesSource(data: payload)

    let stream = MultipartUploadStream(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: "text/plain",
      totalSize: UInt64(payload.count),
      chunkSize: 4
    )

    var firstPass = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      firstPass.writeBuffer(&copy)
    }

    var secondPass = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      secondPass.writeBuffer(&copy)
    }

    #expect(firstPass.readableBytes == secondPass.readableBytes)
    #expect(firstPass == secondPass)
  }

  /// Tests that casting stream.source to an existential copy does not mutate stream.source when source is a value type.
  @Test func existentialCastMutationDoesNotMutateStreamSource() async throws {
    let payload = Data([1, 2, 3, 4, 5, 6, 7, 8])
    let source = BytesSource(data: payload)
    let stream = MultipartUploadStream(
      source: source,
      boundary: "Boundary123",
      metadataJson: Data("{}".utf8),
      contentType: "application/octet-stream",
      totalSize: UInt64(payload.count),
      chunkSize: 4
    )

    // Attempting to mutate stream.source via existential cast (as in performSimpleUpload):
    if var seekable = stream.source as? (any SeekableUploadSource) {
      // Read chunks from the local copy
      let chunk = try await seekable.read(maxBytes: 4)
      #expect(chunk != nil)
      // Seek the local copy
      try await seekable.seek(to: 0)
    }

    // A fresh iterator from stream.source still starts from offset 0, untouched by mutations to `seekable`
    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
  }

  /// Tests that MultipartUploadStream.prepare rewinds a seekable source back to offset 0 even if it had been partially read.
  @Test func multipartUploadStreamPrepareRewindsPartiallyReadSource() async throws {
    let payload = Data([1, 2, 3, 4, 5, 6, 7, 8])
    var source = BytesSource(data: payload)
    // Read 4 bytes beforehand
    _ = try await source.read(maxBytes: 4)

    let prepared = try await MultipartUploadStream.prepare(
      source: source,
      boundary: "BoundaryRewind",
      metadataJson: Data("{}".utf8),
      contentType: "application/octet-stream",
      totalSize: UInt64(payload.count),
      options: .none,
      chunkSize: 4
    )

    var collected = NIOCore.ByteBuffer()
    for try await chunk in prepared.stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(UInt64(collected.readableBytes) == prepared.stream.bodyLength)
  }

  /// Tests that MultipartUploadStream.rewind rewinds a seekable source back to offset 0.
  @Test func multipartUploadStreamRewindRewindsSource() async throws {
    let payload = Data([1, 2, 3, 4, 5, 6, 7, 8])
    var source = BytesSource(data: payload)
    // Read 4 bytes beforehand
    _ = try await source.read(maxBytes: 4)

    var stream = MultipartUploadStream(
      source: source,
      boundary: "BoundaryRewind",
      metadataJson: Data("{}".utf8),
      contentType: "application/octet-stream",
      totalSize: UInt64(payload.count),
      chunkSize: 4
    )

    try await stream.rewind()

    var collected = NIOCore.ByteBuffer()
    for try await chunk in stream {
      var copy = chunk
      collected.writeBuffer(&copy)
    }
    #expect(UInt64(collected.readableBytes) == stream.bodyLength)
  }
}
