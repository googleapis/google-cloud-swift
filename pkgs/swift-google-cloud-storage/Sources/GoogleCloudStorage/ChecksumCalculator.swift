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
import NIOCore
@_spi(GoogleCloudInternal) import struct GoogleGax._CRC32C

/// A protocol for incremental checksum computation.
protocol ChecksumCalculator: Sendable {
  /// The algorithm name matching the HTTP header tag (e.g. "crc32c", "md5").
  var algorithmName: String { get }

  /// Incrementally updates the checksum state from a byte chunk.
  mutating func update(_ buffer: ByteChunk)

  /// Finalizes the checksum and returns the Base64-encoded string.
  func finalize() -> String
}

extension ChecksumCalculator {
  /// Convenience helper for Data chunks.
  mutating func update(_ data: Data) {
    update(ByteChunk(data))
  }

  /// Convenience helper for NIOCore.ByteBuffer chunks.
  mutating func update(_ buffer: NIOCore.ByteBuffer) {
    update(ByteChunk(buffer))
  }
}

/// CRC32C (Castagnoli) checksum calculator.
struct CRC32CCalculator: ChecksumCalculator {
  let algorithmName = "crc32c"
  private var crc32c: _CRC32C

  init(seed: UInt32? = nil) {
    self.crc32c = seed != nil ? _CRC32C(seed: seed!) : _CRC32C()
  }

  mutating func update(_ buffer: ByteChunk) {
    buffer.withUnsafeBytes { crc32c.update($0) }
  }

  func finalize() -> String {
    crc32cBase64(finalizeCRC32C())
  }

  func finalizeCRC32C() -> UInt32 {
    crc32c.finalize()
  }
}

/// MD5 checksum calculator.
struct MD5Calculator: ChecksumCalculator {
  let algorithmName = "md5"
  private var md5 = Insecure.MD5()

  init() {}

  mutating func update(_ buffer: ByteChunk) {
    // SAFETY: `Insecure.MD5.update(bufferPointer:)` is implicitly `@unsafe` due to its
    // `UnsafeRawBufferPointer` parameter; `ByteChunk.withUnsafeBytes` guarantees pointer validity.
    buffer.withUnsafeBytes { unsafe md5.update(bufferPointer: $0) }
  }

  func finalize() -> String {
    finalizeMD5().base64EncodedString()
  }

  func finalizeMD5() -> Data {
    Data(md5.finalize())
  }
}

/// A static checksum calculator that returns a user-provided value without computing.
struct ProvidedChecksumCalculator: ChecksumCalculator {
  let algorithmName: String
  let value: String

  init(algorithmName: String, value: String) {
    self.algorithmName = algorithmName
    let prefix = "\(algorithmName)="
    if value.hasPrefix(prefix) {
      self.value = String(value.dropFirst(prefix.count))
    } else {
      self.value = value
    }
  }

  mutating func update(_ buffer: ByteChunk) {
    // No-op: value is static and already provided
  }

  func finalize() -> String {
    value
  }
}

extension ChecksumOptions {
  func makeUploadCalculators(crc32cSeed: UInt32? = nil) -> [any ChecksumCalculator] {
    var calculators = [any ChecksumCalculator]()
    if let crc = self.crc32c {
      switch crc {
      case .auto:
        calculators.append(CRC32CCalculator(seed: crc32cSeed))
      case .value(let val):
        calculators.append(ProvidedChecksumCalculator(algorithmName: "crc32c", value: val))
      }
    }
    if let md5 = self.md5 {
      switch md5 {
      case .auto:
        calculators.append(MD5Calculator())
      case .value(let val):
        calculators.append(ProvidedChecksumCalculator(algorithmName: "md5", value: val))
      }
    }
    return calculators
  }
}

/// Encodes a 32-bit CRC32C checksum as a Base64 string of its 4 big-endian bytes, matching the
/// representation used by Google Cloud Storage in `x-goog-hash` headers and object metadata.
///
/// This helper constructs the 4-byte array via bitwise shifts rather than `withUnsafeBytes(of:)`
/// to avoid raw pointer operations under `-strict-memory-safety` (SE-0458) and to remain
/// compatible across Swift 6.2/6.3 (where `withUnsafeBytes(of:)` is `@unsafe`) and Swift 6.4+
/// (where `withUnsafeBytes(of:)` is `@safe` and rejects `unsafe` with `[#UnnecessaryUnsafe]`).
func crc32cBase64(_ value: UInt32) -> String {
  Data([
    UInt8((value >> 24) & 0xFF),
    UInt8((value >> 16) & 0xFF),
    UInt8((value >> 8) & 0xFF),
    UInt8(value & 0xFF),
  ]).base64EncodedString()
}

/// Decodes a Base64-encoded 4-byte big-endian CRC32C checksum into a 32-bit unsigned integer,
/// matching the representation used by Google Cloud Storage in `x-goog-hash` headers,
/// `x-goog-running-hash` headers, and object metadata.
///
/// Returns `nil` if `base64` is not a valid Base64-encoded string or if the decoded payload
/// is not exactly 4 bytes.
///
/// Like `crc32cBase64(_:)`, this helper reconstructs the 32-bit value via bitwise shifts rather
/// than `withUnsafeBytes` and `loadUnaligned(as:)` to avoid raw pointer operations under
/// `-strict-memory-safety` (SE-0458).
func crc32cFromBase64(_ base64: String) -> UInt32? {
  guard let data = Data(base64Encoded: base64), data.count == 4 else {
    return nil
  }
  let idx = data.startIndex
  return (UInt32(data[idx]) << 24)
    | (UInt32(data[idx + 1]) << 16)
    | (UInt32(data[idx + 2]) << 8)
    | UInt32(data[idx + 3])
}
