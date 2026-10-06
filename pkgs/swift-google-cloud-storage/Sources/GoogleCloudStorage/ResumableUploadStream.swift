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
import GoogleGax
import NIOCore

struct ResumableUploadStream<S: SeekableWriteObjectSource>: AsyncSequence, Sendable {
  typealias Element = NIOCore.ByteBuffer

  private let source: ChecksummedSource<S>
  private let bytesToRead: UInt64
  private let chunkSize: Int

  init(
    source: ChecksummedSource<S>,
    rangeStart: UInt64,
    rangeEnd: UInt64,
    chunkSize: Int
  ) {
    self.source = source
    self.bytesToRead = (rangeEnd >= rangeStart) ? (rangeEnd - rangeStart + 1) : 0
    self.chunkSize = chunkSize
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private var source: ChecksummedSource<S>
    private let bytesToRead: UInt64
    private let chunkSize: Int
    private var bytesRead: UInt64 = 0

    init(
      source: ChecksummedSource<S>,
      bytesToRead: UInt64,
      chunkSize: Int
    ) {
      self.source = source
      self.bytesToRead = bytesToRead
      self.chunkSize = chunkSize
    }

    mutating func next() async throws -> NIOCore.ByteBuffer? {
      try Task.checkCancellation()
      guard bytesRead < bytesToRead else { return nil }
      let remaining = bytesToRead - bytesRead
      let toRead = Int(Swift.min(UInt64(chunkSize), remaining))
      guard let chunk = try await source.read(maxBytes: toRead), !chunk.isEmpty else {
        if bytesRead < bytesToRead {
          throw WriteObjectError.sourceError(
            WriteObjectSourceError.offsetOutOfBounds(offset: bytesRead, size: bytesToRead))
        }
        return nil
      }
      let effectiveChunk = chunk.count > toRead ? chunk.subdata(in: 0..<toRead) : chunk
      bytesRead += UInt64(effectiveChunk.count)
      return effectiveChunk.byteBuffer
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(
      source: source,
      bytesToRead: bytesToRead,
      chunkSize: chunkSize
    )
  }
}
