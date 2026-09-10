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
  public var totalSize: UInt64? {
    return UInt64(buffer.count)
  }
  private var offset: UInt64 = 0

  public init(buffer: ByteBuffer) {
    self.buffer = buffer
  }

  public init(data: Data) {
    self.buffer = ByteBuffer(data)
  }

  public mutating func read(maxBytes: Int) async throws -> ByteBuffer? {
    guard maxBytes > 0, offset < UInt64(buffer.count) else { return nil }
    let end = min(offset + UInt64(maxBytes), UInt64(buffer.count))
    let chunk = buffer.subdata(in: Int(offset)..<Int(end))
    offset = end
    return chunk
  }

  public mutating func seek(to offset: UInt64) async throws {
    let size = UInt64(buffer.count)
    guard offset <= size else {
      throw UploadError.localSourceTooSmall(localSize: size, gcsOffset: offset)
    }
    self.offset = offset
  }
}
