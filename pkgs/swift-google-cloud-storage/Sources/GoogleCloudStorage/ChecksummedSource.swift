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
import Synchronization

struct ChunkInfo: Sendable {
  let data: ByteChunk
  let isLast: Bool
  let checksum: String?
}

/// Thread-safe tracker that manages checksum calculators and validation across chunked and streaming uploads.
final class ChecksumTracker: Sendable {
  struct State: Sendable {
    var calculators: [any ChecksumCalculator]
    var bytesHashed: UInt64 = 0
    var finalizedChecksum: String? = nil
  }

  private let state: Mutex<State>

  init(calculators: [any ChecksumCalculator]) {
    self.state = Mutex(State(calculators: calculators))
  }

  var bytesHashed: UInt64 {
    state.withLock { $0.bytesHashed }
  }

  var hasCalculators: Bool {
    state.withLock { !$0.calculators.isEmpty }
  }

  func update(data: ByteChunk, startOffset: UInt64) {
    state.withLock { s in
      guard !s.calculators.isEmpty else { return }
      let endOffset = startOffset + UInt64(data.count)
      guard endOffset > s.bytesHashed else { return }

      let unhashedData: ByteChunk
      if startOffset >= s.bytesHashed {
        unhashedData = data
      } else {
        let offsetInChunk = Int(s.bytesHashed - startOffset)
        unhashedData = data.subdata(in: offsetInChunk..<data.count)
      }

      for i in s.calculators.indices {
        s.calculators[i].update(unhashedData)
      }
      s.bytesHashed = endOffset
    }
  }

  func seedCRC32C(seed: UInt32, bytesHashed: UInt64) {
    state.withLock { s in
      s.bytesHashed = bytesHashed
      s.calculators = s.calculators.compactMap { calc in
        if calc is CRC32CCalculator {
          return CRC32CCalculator(seed: seed)
        }
        if calc is ProvidedChecksumCalculator {
          return calc
        }
        return nil
      }
    }
  }

  func finalizeChecksum() -> String? {
    state.withLock { s in
      if let existing = s.finalizedChecksum { return existing }
      guard !s.calculators.isEmpty else { return nil }
      let result = s.calculators.map { "\($0.algorithmName)=\($0.finalize())" }.joined(
        separator: ", ")
      s.finalizedChecksum = result
      return result
    }
  }

  func finalizeCRC32C() -> UInt32? {
    state.withLock { s in
      for calc in s.calculators {
        if let crc = calc as? CRC32CCalculator {
          return crc.finalizeCRC32C()
        }
      }
      return nil
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

struct ChecksummedSource<S: WriteObjectSource>: Sendable where S: Sendable {
  var source: S
  let options: ChecksumOptions
  private let tracker: ChecksumTracker
  private var nextChunk: ByteChunk? = nil
  private var isInitialized = false
  private var nextChunkOffset: UInt64 = 0

  init(source: S, options: ChecksumOptions) {
    self.source = source
    self.options = options
    self.tracker = ChecksumTracker(calculators: options.makeUploadCalculators())
  }

  var bytesHashed: UInt64 {
    tracker.bytesHashed
  }

  /// Reseeds the CRC32C calculator with a running hash seed provided by GCS.
  ///
  /// Because the other hash algorithm used by Cloud Storage (MD5) does not support
  /// intermediate running seeds from GCS, any dynamic non-seedable calculators are discarded
  /// to prevent corruption when `bytesHashed` is rewound.
  mutating func seedCRC32C(seed: UInt32, bytesHashed: UInt64) {
    tracker.seedCRC32C(seed: seed, bytesHashed: bytesHashed)
  }

  /// Direct read without lookahead: reads from `source`, hashes the chunk, and advances offset.
  mutating func read(maxBytes: Int) async throws -> ByteChunk? {
    let chunk: ByteChunk?
    do {
      chunk = try await source.read(maxBytes: maxBytes)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw WriteObjectError.fromSourceError(error)
    }
    guard let chunk, !chunk.isEmpty else {
      return nil
    }
    let offset = nextChunkOffset
    nextChunkOffset += UInt64(chunk.count)
    tracker.update(data: chunk, startOffset: offset)
    return chunk
  }

  mutating func readChunk(maxBytes: Int) async throws -> ChunkInfo? {
    // If the total size of the source is known, detect `isLast` without lookahead.
    if let total = source.totalSize {
      guard let currentChunk = try await read(maxBytes: maxBytes), !currentChunk.isEmpty else {
        return nil
      }
      let isLast = nextChunkOffset >= total
      let checksumStr = isLast ? finalizeChecksum() : nil
      return ChunkInfo(data: currentChunk, isLast: isLast, checksum: checksumStr)
    }

    // Fallback lookahead for unknown-size streams.
    if !isInitialized {
      do {
        nextChunk = try await source.read(maxBytes: maxBytes)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw WriteObjectError.fromSourceError(error)
      }
      isInitialized = true
    }

    guard let currentChunk = nextChunk, !currentChunk.isEmpty else {
      return nil
    }

    let currentChunkOffset = nextChunkOffset
    nextChunkOffset += UInt64(currentChunk.count)

    do {
      nextChunk = try await source.read(maxBytes: maxBytes)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw WriteObjectError.fromSourceError(error)
    }
    let isLast = nextChunk == nil || nextChunk!.isEmpty

    tracker.update(data: currentChunk, startOffset: currentChunkOffset)

    let checksumStr = isLast ? finalizeChecksum() : nil
    return ChunkInfo(data: currentChunk, isLast: isLast, checksum: checksumStr)
  }

  mutating func finalizeChecksum() -> String? {
    tracker.finalizeChecksum()
  }

  func validate(object: Object) throws {
    try tracker.validate(object: object)
  }
}

extension ChecksummedSource where S: SeekableWriteObjectSource {
  /// Repositions the stream offset for subsequent read operations.
  ///
  /// - If `offset > bytesHashed`, catches up checksum computation by reading and hashing
  ///   all bytes from `bytesHashed` up to `offset`.
  /// - If `offset <= bytesHashed` (seeking backward), repositions the underlying source but
  ///   leaves `bytesHashed` unchanged. When the stream is subsequently re-read,
  ///   `updateChecksums` will skip the already-hashed bytes `offset ..< bytesHashed`, preventing
  ///   duplicate accumulation into the hash calculators.
  mutating func seek(to offset: UInt64) async throws {
    nextChunk = nil
    isInitialized = false
    nextChunkOffset = offset

    guard offset > tracker.bytesHashed && tracker.hasCalculators else {
      do {
        try await source.seek(to: offset)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw WriteObjectError.fromSourceError(error)
      }
      return
    }

    // Catch up checksum calculation from `bytesHashed` to `offset`
    do {
      try await source.seek(to: tracker.bytesHashed)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw WriteObjectError.fromSourceError(error)
    }
    var currentSeekOffset = tracker.bytesHashed
    var bytesRemaining = offset - tracker.bytesHashed
    let bufferSize: UInt64 = 8 * 1024 * 1024
    while bytesRemaining > 0 {
      let toRead = Int(min(bytesRemaining, bufferSize))
      let chunk: ByteChunk?
      do {
        chunk = try await source.read(maxBytes: toRead)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw WriteObjectError.fromSourceError(error)
      }
      guard let chunk, !chunk.isEmpty else {
        throw WriteObjectError.sourceError(
          WriteObjectSourceError.offsetOutOfBounds(offset: offset, size: currentSeekOffset))
      }
      tracker.update(data: chunk, startOffset: currentSeekOffset)
      currentSeekOffset += UInt64(chunk.count)
      bytesRemaining -= UInt64(chunk.count)
    }
  }
}
