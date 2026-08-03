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

import Crypto
import Foundation
@_spi(GoogleCloudInternal) import struct GoogleCloudGax._CRC32C

struct ChunkInfo: Sendable {
  let data: Data
  let isLast: Bool
  let checksum: String?
}

struct ChecksummedSource<S: UploadSource> {
  var source: S
  let options: ChecksumOptions
  private var md5 = Insecure.MD5()
  private var crc32c = _CRC32C()
  private var nextChunk: Data? = nil
  private var isInitialized = false
  private var isFinished = false
  private var bytesHashed: Int64 = 0
  private var nextChunkOffset: Int64 = 0

  init(source: S, options: ChecksumOptions) {
    self.source = source
    self.options = options
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
  }

  mutating func seedCRC32C(seed: UInt32, bytesHashed: Int64) {
    if options.crc32c == .auto {
      self.crc32c = _CRC32C(seed: seed)
      self.bytesHashed = bytesHashed
    }
  }

  private mutating func updateChecksums(data: Data, startOffset: Int64) {
    let needCRC32C = (options.crc32c == .auto)
    let needMD5 = (options.md5 == .auto)
    guard needCRC32C || needMD5 else { return }

    let endOffset = startOffset + Int64(data.count)
    guard endOffset > bytesHashed else { return }

    let unhashedData: Data
    if startOffset >= bytesHashed {
      unhashedData = data
    } else {
      let offsetInChunk = Int(bytesHashed - startOffset)
      unhashedData = data.subdata(in: offsetInChunk..<data.count)
    }

    if needCRC32C {
      crc32c.update(unhashedData)
    }
    if needMD5 {
      md5.update(data: unhashedData)
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
    nextChunkOffset += Int64(currentChunk.count)

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
    var parts = [String]()

    if let crcOption = options.crc32c {
      switch crcOption {
      case .auto:
        let bigEndian = crc32c.finalize().bigEndian
        var bytes = [UInt8]()
        withUnsafeBytes(of: bigEndian) {
          bytes = Array($0)
        }
        parts.append("crc32c=" + Data(bytes).base64EncodedString())
      case .value(let val):
        let formatted = val.hasPrefix("crc32c=") ? val : "crc32c=" + val
        parts.append(formatted)
      }
    }

    if let md5Option = options.md5 {
      switch md5Option {
      case .auto:
        let digest = md5.finalize()
        parts.append("md5=" + Data(digest).base64EncodedString())
      case .value(let val):
        let formatted = val.hasPrefix("md5=") ? val : "md5=" + val
        parts.append(formatted)
      }
    }

    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

extension ChecksummedSource where S: SeekableUploadSource {
  mutating func seek(to offset: Int64) async throws {
    nextChunk = nil
    isInitialized = false
    isFinished = false
    nextChunkOffset = offset

    let needCRC32C = (options.crc32c == .auto)
    let needMD5 = (options.md5 == .auto)

    guard offset > bytesHashed && (needCRC32C || needMD5) else {
      try await source.seek(to: offset)
      return
    }

    // Catch up checksum calculation from `bytesHashed` to `offset`
    try await source.seek(to: bytesHashed)
    var currentSeekOffset = bytesHashed
    var bytesRemaining = offset - bytesHashed
    let bufferSize = 8 * 1024 * 1024
    while bytesRemaining > 0 {
      let toRead = Int(min(bytesRemaining, Int64(bufferSize)))
      guard let chunk = try await source.read(maxBytes: toRead), !chunk.isEmpty else {
        throw UploadError.localSourceTooSmall(localSize: currentSeekOffset, gcsOffset: offset)
      }
      updateChecksums(data: chunk, startOffset: currentSeekOffset)
      currentSeekOffset += Int64(chunk.count)
      bytesRemaining -= Int64(chunk.count)
    }
  }
}
