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

import CGoogleGaxCRC32C
public import Foundation

/// A hardware-accelerated and lookup-table based implementation of the CRC32C (Castagnoli) checksum algorithm.
@_spi(GoogleCloudInternal) public struct _CRC32C: Sendable {
  /// Whether hardware acceleration is supported and active on the current host CPU.
  /// Dynamically detected once per process.
  static let isHardwareAccelerated: Bool = googleGax_crc32c_hw_available()

  private static let table: [UInt32] = {
    (0..<256).map { i in
      var crc = UInt32(i)
      for _ in 0..<8 {
        crc = (crc & 1 != 0) ? (crc >> 1) ^ 0x82F63B78 : (crc >> 1)
      }
      return crc
    }
  }()

  private var value: UInt32

  public init(seed: UInt32 = 0) {
    self.value = seed ^ 0xFFFF_FFFF
  }

  public mutating func update(_ data: Data) {
    data.withUnsafeBytes { buffer in
      update(buffer)
    }
  }

  public mutating func update(_ buffer: UnsafeRawBufferPointer) {
    guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else { return }
    if Self.isHardwareAccelerated {
      value = googleGax_crc32c_hw(value, baseAddress, buffer.count)
    } else {
      updateSoftware(buffer)
    }
  }

  mutating func updateSoftware(_ buffer: UnsafeRawBufferPointer) {
    for byte in buffer {
      let index = Int(UInt8(value & 0xFF) ^ byte)
      value = (value >> 8) ^ Self.table[index]
    }
  }

  /// Returns the computed CRC32C checksum.
  ///
  /// This method is non-destructive: calling it does not alter the internal checksum state.
  /// Subsequent calls to `finalize()` will return the same value, and subsequent `update`
  /// operations can continue streaming data incrementally.
  public func finalize() -> UInt32 {
    return value ^ 0xFFFF_FFFF
  }

  public static func compute(_ data: Data) -> UInt32 {
    var crc = Self()
    crc.update(data)
    return crc.finalize()
  }

  public static func compute(_ buffer: UnsafeRawBufferPointer) -> UInt32 {
    var crc = Self()
    crc.update(buffer)
    return crc.finalize()
  }

  static func computeSoftware(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { buffer in
      computeSoftware(buffer)
    }
  }

  static func computeSoftware(_ buffer: UnsafeRawBufferPointer) -> UInt32 {
    var crc = Self()
    crc.updateSoftware(buffer)
    return crc.finalize()
  }
}
