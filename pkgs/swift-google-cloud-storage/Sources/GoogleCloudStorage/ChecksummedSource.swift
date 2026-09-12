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

struct ChunkInfo: Sendable {
  let data: ByteBuffer
  let isLast: Bool
  let checksum: String?
}

struct ChecksummedSource<S: UploadSource> {
  var source: S
  let options: ChecksumOptions
  private var calculators: [any ChecksumCalculator] = []
  private var nextChunk: ByteBuffer? = nil
  private var isInitialized = false
  private var isFinished = false
  /// The high-water mark of sequentially processed bytes in `calculators`.
  /// All bytes in `0 ..< bytesHashed` have already been fed into the checksum calculators.
  /// When seeking backward (`offset < bytesHashed`), `bytesHashed` is not decremented,
  /// ensuring that re-reading previously hashed bytes will not cause duplicate hashing.
  private var bytesHashed: UInt64 = 0
  private var nextChunkOffset: UInt64 = 0

  init(source: S, options: ChecksumOptions) {
    self.source = source
    self.options = options
    self.calculators = options.makeUploadCalculators()
  }

  init(source: S, validation: ChecksumValidation) {
    self.source = source
    switch validation {
    case .none:
      self.options = .none
    case .crc32c:
      self.options = ChecksumOptions(crc32c: .auto, md5: nil)
    case .md5:
      self.options = ChecksumOptions(crc32c: nil, md5: .auto)
    }
    self.calculators = self.options.makeUploadCalculators()
  }

  /// Reseeds the CRC32C calculator with a running hash seed provided by GCS.
  ///
  /// Because the other hash algorithm used by Cloud Storage (MD5) does not support
  /// intermediate running seeds from GCS, any dynamic non-seedable calculators are discarded
  /// to prevent corruption when `bytesHashed` is rewound.
  mutating func seedCRC32C(seed: UInt32, bytesHashed: UInt64) {
    self.bytesHashed = bytesHashed
    self.calculators = self.calculators.compactMap { calc in
      if calc is CRC32CCalculator {
        return CRC32CCalculator(seed: seed)
      }
      if calc is ProvidedChecksumCalculator {
        return calc
      }
      // Non-seedable dynamic calculators (e.g. MD5) are discarded because their state
      // cannot be rolled back to `bytesHashed`.
      return nil
    }
  }

  /// Incrementally feeds new data into the checksum calculators.
  ///
  /// To support seeking backward and retrying chunk uploads without corrupting checksums,
  /// this method skips any prefix of `data` that falls below `bytesHashed` (the high-water mark
  /// of bytes already fed into `calculators`). Only bytes beyond `bytesHashed` are accumulated.
  private mutating func updateChecksums(data: ByteBuffer, startOffset: UInt64) {
    guard !calculators.isEmpty else { return }

    let endOffset = startOffset + UInt64(data.count)
    guard endOffset > bytesHashed else { return }

    let unhashedData: ByteBuffer
    if startOffset >= bytesHashed {
      unhashedData = data
    } else {
      let offsetInChunk = Int(bytesHashed - startOffset)
      unhashedData = data.subdata(in: offsetInChunk..<data.count)
    }

    for i in calculators.indices {
      calculators[i].update(unhashedData)
    }

    bytesHashed = endOffset
  }

  mutating func readChunk(maxBytes: Int) async throws -> ChunkInfo? {
    if !isInitialized {
      nextChunk = try await source.read(maxBytes: maxBytes)
      isInitialized = true
    }

    guard let currentChunk = nextChunk, !currentChunk.isEmpty else {
      return nil
    }

    let currentChunkOffset = nextChunkOffset
    nextChunkOffset += UInt64(currentChunk.count)

    nextChunk = try await source.read(maxBytes: maxBytes)
    let isLast = nextChunk == nil || nextChunk!.isEmpty

    updateChecksums(data: currentChunk, startOffset: currentChunkOffset)

    var checksumStr: String? = nil
    if isLast {
      checksumStr = finalizeChecksum()
    }

    return ChunkInfo(data: currentChunk, isLast: isLast, checksum: checksumStr)
  }

  mutating func finalizeChecksum() -> String? {
    guard !isFinished else { return nil }
    isFinished = true
    guard !calculators.isEmpty else { return nil }
    return calculators.map { "\($0.algorithmName)=\($0.finalize())" }.joined(separator: ", ")
  }
}

extension ChecksummedSource where S: SeekableUploadSource {
  /// Repositions the stream offset for subsequent `readChunk` operations.
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
    isFinished = false
    nextChunkOffset = offset

    guard offset > bytesHashed && !calculators.isEmpty else {
      try await source.seek(to: offset)
      return
    }

    // Catch up checksum calculation from `bytesHashed` to `offset`
    try await source.seek(to: bytesHashed)
    var currentSeekOffset = bytesHashed
    var bytesRemaining = offset - bytesHashed
    let bufferSize: UInt64 = 8 * 1024 * 1024
    while bytesRemaining > 0 {
      let toRead = Int(min(bytesRemaining, bufferSize))
      guard let chunk = try await source.read(maxBytes: toRead), !chunk.isEmpty else {
        throw UploadError.localSourceTooSmall(localSize: currentSeekOffset, gcsOffset: offset)
      }
      updateChecksums(data: chunk, startOffset: currentSeekOffset)
      currentSeekOffset += UInt64(chunk.count)
      bytesRemaining -= UInt64(chunk.count)
    }
  }
}
