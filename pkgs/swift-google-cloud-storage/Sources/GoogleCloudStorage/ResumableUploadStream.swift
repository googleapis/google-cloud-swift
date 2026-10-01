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
@_spi(GoogleCloudInternal) import struct GoogleGax._CRC32C
import NIOCore
import Synchronization

final class UploadChecksumTracker: Sendable {
  struct State: Sendable {
    var crc32c: _CRC32C?
    var bytesHashed: UInt64 = 0
  }

  private let state: Mutex<State>

  init(crc32cSeed: UInt32? = nil, trackCrc32c: Bool) {
    var s = State()
    if trackCrc32c {
      s.crc32c = crc32cSeed != nil ? _CRC32C(seed: crc32cSeed!) : _CRC32C()
    }
    self.state = Mutex(s)
  }

  func update(_ chunk: ByteChunk) {
    state.withLock { s in
      chunk.withUnsafeBytes { raw in
        s.crc32c?.update(raw)
      }
      s.bytesHashed += UInt64(chunk.count)
    }
  }

  func finalizeCRC32C() -> UInt32? {
    state.withLock { s in
      s.crc32c?.finalize()
    }
  }

  func validate(object: Object) throws {
    guard let computed = finalizeCRC32C() else { return }
    if let serverCRC = object.checksums?.crc32C {
      if computed != serverCRC {
        throw WriteObjectError.unexpectedServerResponse(
          statusCode: 200,
          message:
            "Checksum mismatch: calculated CRC32C \(computed) does not match server returned \(serverCRC)"
        )
      }
    }
  }
}

struct ResumableUploadStream<S: SeekableWriteObjectSource>: AsyncSequence, Sendable {
  typealias Element = NIOCore.ByteBuffer

  var source: S
  let rangeStart: UInt64
  let rangeEnd: UInt64
  let chunkSize: Int
  let tracker: UploadChecksumTracker?

  struct AsyncIterator: AsyncIteratorProtocol {
    private var source: S
    private let bytesToRead: UInt64
    private let chunkSize: Int
    private var bytesRead: UInt64 = 0
    private let tracker: UploadChecksumTracker?

    init(
      source: S,
      bytesToRead: UInt64,
      chunkSize: Int,
      tracker: UploadChecksumTracker?
    ) {
      self.source = source
      self.bytesToRead = bytesToRead
      self.chunkSize = chunkSize
      self.tracker = tracker
    }

    mutating func next() async throws -> NIOCore.ByteBuffer? {
      guard bytesRead < bytesToRead else { return nil }
      let remaining = bytesToRead - bytesRead
      let toRead = Int(Swift.min(UInt64(chunkSize), remaining))
      let chunk: ByteChunk?
      do {
        chunk = try await source.read(maxBytes: toRead)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw WriteObjectError.fromSourceError(error)
      }
      guard let chunk, !chunk.isEmpty else {
        if bytesRead < bytesToRead {
          throw WriteObjectError.sourceError(
            WriteObjectSourceError.offsetOutOfBounds(offset: bytesRead, size: bytesToRead))
        }
        return nil
      }
      bytesRead += UInt64(chunk.count)
      tracker?.update(chunk)
      return chunk.byteBuffer
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    let bytesToRead = (rangeEnd >= rangeStart) ? (rangeEnd - rangeStart + 1) : 0
    return AsyncIterator(
      source: source,
      bytesToRead: bytesToRead,
      chunkSize: chunkSize,
      tracker: tracker
    )
  }
}
