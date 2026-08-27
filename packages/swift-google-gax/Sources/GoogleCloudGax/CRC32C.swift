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

/// A lookup-table based implementation of the CRC32C (Castagnoli) checksum algorithm.
// TODO(https://github.com/googleapis/google-cloud-swift/issues/38) - Use hardware accelerated
//   CRC32C on supported platforms.
@_spi(GoogleCloudInternal) public struct _CRC32C: Sendable {
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
    for byte in data {
      let index = Int(UInt8(value & 0xFF) ^ byte)
      value = (value >> 8) ^ Self.table[index]
    }
  }

  public mutating func update(_ buffer: UnsafeRawBufferPointer) {
    for byte in buffer {
      let index = Int(UInt8(value & 0xFF) ^ byte)
      value = (value >> 8) ^ Self.table[index]
    }
  }

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
}
