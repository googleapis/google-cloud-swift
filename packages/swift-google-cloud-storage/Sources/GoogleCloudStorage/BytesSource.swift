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
