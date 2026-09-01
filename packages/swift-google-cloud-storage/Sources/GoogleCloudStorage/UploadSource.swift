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
import NIOCore

/// Represents a data source that can be read from sequentially.
public protocol UploadSource: Sendable {
  /// Reads the next chunk of data, up to `maxBytes`.
  /// Returns `nil` when the source is exhausted.
  mutating func read(maxBytes: Int) async throws -> ByteBuffer?

  /// The total size of the source, if known.
  var totalSize: Int64? { get }
}

/// Represents an upload source that supports seeking (rewinding/skipping).
/// Conformance to this protocol enables persistent resumption.
public protocol SeekableUploadSource: UploadSource {
  /// Seeks to a specific byte offset.
  mutating func seek(to offset: Int64) async throws
}

/// An upload source that reads from a local file.
public struct FileSource: SeekableUploadSource {
  public let fileURL: URL
  private var offset: Int64 = 0

  public var totalSize: Int64? {
    do {
      let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
      return values.fileSize.map { Int64($0) }
    } catch {
      return nil
    }
  }

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seek(toOffset: UInt64(offset))
    guard let data = try handle.read(upToCount: maxBytes), !data.isEmpty else {
      return nil
    }
    offset += Int64(data.count)
    return ByteBuffer(data)
  }

  public mutating func seek(to offset: Int64) async throws {
    guard offset >= 0 else {
      throw UploadError.internalError("Invalid seek offset: \(offset)")
    }
    if let size = totalSize, offset > size {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}

/// An upload source that wraps in-memory bytes or buffers.
public struct BytesSource: SeekableUploadSource {
  public let buffer: ByteBuffer
  public var totalSize: Int64? {
    return Int64(buffer.count)
  }
  private var offset: Int64 = 0

  public init(buffer: ByteBuffer) {
    self.buffer = buffer
  }

  public init(data: Data) {
    self.buffer = ByteBuffer(data)
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard maxBytes > 0, offset < buffer.count else { return nil }
    let end = min(offset + Int64(maxBytes), Int64(buffer.count))
    let countToRead = Int(end - offset)
    let chunk: ByteBuffer
    switch buffer.storage {
    case .data(let data):
      chunk = ByteBuffer(data.subdata(in: Int(offset)..<Int(end)))
    case .byteBuffer(let nioBuffer):
      var slice = nioBuffer
      slice.moveReaderIndex(to: nioBuffer.readerIndex + Int(offset))
      if let subSlice = slice.readSlice(length: countToRead) {
        chunk = ByteBuffer(subSlice)
      } else {
        chunk = ByteBuffer()
      }
    }
    offset = end
    return chunk
  }

  public mutating func seek(to offset: Int64) async throws {
    guard offset >= 0 else {
      throw UploadError.internalError("Invalid seek offset: \(offset)")
    }
    let size = Int64(buffer.count)
    guard offset <= size else {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}

/// An upload source that wraps an arbitrary AsyncSequence of ByteBuffer, Data, or NIOCore.ByteBuffer chunks.
public struct StreamSource: UploadSource {
  private final class StateBox: @unchecked Sendable {
    var nextChunk: () async throws -> NIOCore.ByteBuffer?

    init(nextChunk: @escaping () async throws -> NIOCore.ByteBuffer?) {
      self.nextChunk = nextChunk
    }
  }

  public var totalSize: Int64? { return totalSizeValue }
  private let totalSizeValue: Int64?
  private let stateBox: StateBox
  private var buffer = NIOCore.ByteBuffer()

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: Int64? = nil
  ) where S.Element == ByteBuffer {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      guard let next = try await iterator.next() else { return nil }
      return next.byteBuffer
    }
  }

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: Int64? = nil
  ) where S.Element == Data {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      guard let next = try await iterator.next() else { return nil }
      return ByteBuffer(next).byteBuffer
    }
  }

  public init<S: AsyncSequence & Sendable>(
    sequence: S,
    totalSize: Int64? = nil
  ) where S.Element == NIOCore.ByteBuffer {
    self.totalSizeValue = totalSize
    var iterator = sequence.makeAsyncIterator()
    self.stateBox = StateBox {
      try await iterator.next()
    }
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard maxBytes > 0 else { return nil }
    while buffer.readableBytes < maxBytes {
      guard let nextChunk = try await stateBox.nextChunk() else {
        break
      }
      var next = nextChunk
      buffer.writeBuffer(&next)
    }

    guard buffer.readableBytes > 0 else {
      return nil
    }

    let chunkSize = min(maxBytes, buffer.readableBytes)
    guard let slice = buffer.readSlice(length: chunkSize) else {
      return nil
    }
    return ByteBuffer(slice)
  }
}
