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
@_spi(GoogleCloudInternal) import GoogleCloudGax
import NIOCore

/// Holds the prepared MultipartUploadStream and optional calculated checksum header.
struct PreparedMultipartUpload: Sendable {
  let stream: MultipartUploadStream
  let checksum: String?
}

/// An AsyncSequence that frames an UploadSource with multipart/related boundaries on the fly.
struct MultipartUploadStream: AsyncSequence, Sendable {
  typealias Element = NIOCore.ByteBuffer

  let source: any UploadSource
  let boundary: String
  let metadataJson: Data
  let contentType: String
  let totalSize: Int64
  let chunkSize: Int

  init(
    source: any UploadSource,
    boundary: String,
    metadataJson: Data,
    contentType: String,
    totalSize: Int64,
    chunkSize: Int = 64 * 1024
  ) {
    self.source = source
    self.boundary = boundary
    self.metadataJson = metadataJson
    self.contentType = contentType
    self.totalSize = totalSize
    self.chunkSize = chunkSize
  }

  /// Computes the exact Content-Length for the multipart request body.
  var bodyLength: Int64 {
    let preambleLen =
      "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8.count
      + metadataJson.count
      + "\r\n--\(boundary)\r\nContent-Type: \(contentType)\r\n\r\n".utf8.count
    let epilogueLen = "\r\n--\(boundary)--\r\n".utf8.count
    return Int64(preambleLen) + totalSize + Int64(epilogueLen)
  }

  /// Prepares an upload source for a simple multipart upload by calculating or extracting the `x-goog-hash` header.
  ///
  /// The GCS JSON API simple upload endpoint requires the `x-goog-hash` header to be sent in the initial HTTP request
  /// headers before the request body is received. This helper computes or extracts the required checksum, prepares
  /// the source for streaming, and constructs the `MultipartUploadStream`.
  static func prepare(
    source: any UploadSource,
    boundary: String,
    metadataJson: Data,
    contentType: String,
    totalSize: Int64,
    options: ChecksumOptions,
    chunkSize: Int = 64 * 1024
  ) async throws -> PreparedMultipartUpload {
    var calculators = options.makeUploadCalculators()
    var preparedSource: any UploadSource = source

    // Only inspect/read the source if automatic checksum computation is needed.
    let autoCalculators = calculators.filter { !($0 is ProvidedChecksumCalculator) }
    if !autoCalculators.isEmpty {
      if var seekable = source as? (any SeekableUploadSource) {
        while let chunk = try await seekable.read(maxBytes: chunkSize) {
          for i in calculators.indices {
            calculators[i].update(chunk)
          }
        }
        try await seekable.seek(to: 0)
        preparedSource = seekable
      } else {
        var nonSeekable = source
        var buffer = NIOCore.ByteBuffer()
        while let chunk = try await nonSeekable.read(maxBytes: chunkSize) {
          for i in calculators.indices {
            calculators[i].update(chunk)
          }
          var nio = chunk.byteBuffer
          buffer.writeBuffer(&nio)
        }
        preparedSource = BytesSource(buffer: ByteBuffer(buffer))
      }
    }

    let checksum =
      calculators.isEmpty
      ? nil
      : calculators.map { "\($0.algorithmName)=\($0.finalize())" }.joined(separator: ", ")

    let stream = MultipartUploadStream(
      source: preparedSource,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: contentType,
      totalSize: totalSize,
      chunkSize: chunkSize
    )
    return PreparedMultipartUpload(stream: stream, checksum: checksum)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private enum State {
      case preamble
      case body
      case epilogue
      case done
    }

    private var state: State = .preamble
    private var source: any UploadSource
    private let boundary: String
    private let metadataJson: Data
    private let contentType: String
    private let totalSize: Int64
    private let chunkSize: Int
    private var bytesYielded: Int64 = 0

    init(
      source: any UploadSource,
      boundary: String,
      metadataJson: Data,
      contentType: String,
      totalSize: Int64,
      chunkSize: Int
    ) {
      self.source = source
      self.boundary = boundary
      self.metadataJson = metadataJson
      self.contentType = contentType
      self.totalSize = totalSize
      self.chunkSize = chunkSize
    }

    mutating func next() async throws -> NIOCore.ByteBuffer? {
      switch state {
      case .preamble:
        state = .body
        let preamble = "--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
        let middle = "\r\n--\(boundary)\r\nContent-Type: \(contentType)\r\n\r\n"
        let capacity = preamble.utf8.count + metadataJson.count + middle.utf8.count
        var buffer = ByteBufferAllocator().buffer(capacity: capacity)
        buffer.writeString(preamble)
        _ = metadataJson.withUnsafeBytes { buffer.writeBytes($0) }
        buffer.writeString(middle)
        return buffer

      case .body:
        let chunk: ByteBuffer?
        chunk = try await source.read(maxBytes: chunkSize)
        if let chunk = chunk, !chunk.isEmpty {
          bytesYielded += Int64(chunk.count)
          return chunk.byteBuffer
        }
        if bytesYielded < totalSize {
          throw UploadError.internalError("Failed to read data from source")
        }
        state = .epilogue
        return try await next()

      case .epilogue:
        state = .done
        let epilogue = "\r\n--\(boundary)--\r\n"
        var buffer = ByteBufferAllocator().buffer(capacity: epilogue.utf8.count)
        buffer.writeString(epilogue)
        return buffer

      case .done:
        return nil
      }
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(
      source: source,
      boundary: boundary,
      metadataJson: metadataJson,
      contentType: contentType,
      totalSize: totalSize,
      chunkSize: chunkSize
    )
  }
}
