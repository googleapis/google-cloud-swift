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

  mutating func readChunk(maxBytes: Int) async throws -> ChunkInfo? {
    if !isInitialized {
      nextChunk = try await source.read(maxBytes: maxBytes)
      isInitialized = true
    }

    guard let currentChunk = nextChunk, !currentChunk.isEmpty else {
      return nil
    }

    nextChunk = try await source.read(maxBytes: maxBytes)
    let isLast = nextChunk == nil || nextChunk!.isEmpty

    if options.crc32c == .auto {
      crc32c.update(currentChunk)
    }
    if options.md5 == .auto {
      md5.update(data: currentChunk)
    }

    var checksumStr: String? = nil
    if isLast {
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

      if !parts.isEmpty {
        checksumStr = parts.joined(separator: ", ")
      }
      isFinished = true
    }

    return ChunkInfo(data: currentChunk, isLast: isLast, checksum: checksumStr)
  }
}
