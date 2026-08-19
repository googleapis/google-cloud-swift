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

/// A protocol for incremental checksum computation.
protocol ChecksumCalculator: Sendable {
  /// The algorithm name matching the HTTP header tag (e.g. "crc32c", "md5").
  var algorithmName: String { get }

  /// Incrementally updates the checksum state from raw memory.
  mutating func update(_ buffer: UnsafeRawBufferPointer)

  /// Finalizes the checksum and returns the Base64-encoded string.
  func finalize() -> String
}

extension ChecksumCalculator {
  /// Convenience helper for Data chunks.
  mutating func update(_ data: Data) {
    data.withUnsafeBytes { update($0) }
  }
}

/// CRC32C (Castagnoli) checksum calculator.
struct CRC32CCalculator: ChecksumCalculator {
  let algorithmName = "crc32c"
  private var crc32c: _CRC32C

  init(seed: UInt32? = nil) {
    self.crc32c = seed != nil ? _CRC32C(seed: seed!) : _CRC32C()
  }

  mutating func update(_ buffer: UnsafeRawBufferPointer) {
    crc32c.update(buffer)
  }

  func finalize() -> String {
    let bigEndian = crc32c.finalize().bigEndian
    return withUnsafeBytes(of: bigEndian) { Data($0).base64EncodedString() }
  }
}

/// MD5 checksum calculator.
struct MD5Calculator: ChecksumCalculator {
  let algorithmName = "md5"
  private var md5 = Insecure.MD5()

  init() {}

  mutating func update(_ buffer: UnsafeRawBufferPointer) {
    md5.update(bufferPointer: buffer)
  }

  func finalize() -> String {
    Data(md5.finalize()).base64EncodedString()
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

  mutating func update(_ buffer: UnsafeRawBufferPointer) {
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
