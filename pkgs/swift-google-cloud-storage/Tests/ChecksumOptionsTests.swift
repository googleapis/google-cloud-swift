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
@testable import GoogleCloudStorage
import Testing

@Suite struct ChecksumOptionsTests {
  @Test func defaultInitialization() {
    let options = ChecksumOptions()
    #expect(options.crc32c == .auto)
    #expect(options.md5 == nil)
    #expect(options == ChecksumOptions.default)
  }

  @Test func offOptions() {
    let options = ChecksumOptions.off
    #expect(options.crc32c == nil)
    #expect(options.md5 == nil)
  }

  @Test func customInitialization() {
    let options = ChecksumOptions(crc32c: "crc_base64", md5: "md5_base64")
    #expect(options.crc32c == .value("crc_base64"))
    #expect(options.md5 == .value("md5_base64"))
  }

  @Test func crc32cValueAutoAndValue() {
    let auto = ChecksumOptions.CRC32CValue.auto
    let val = ChecksumOptions.CRC32CValue.value("test")

    #expect(auto != val)
    #expect(val == .value("test"))
  }

  @Test func crc32cValueStringLiteral() {
    let val: ChecksumOptions.CRC32CValue = "my_checksum"
    #expect(val == .value("my_checksum"))
  }

  @Test func crc32cValueUInt32Init() {
    let intVal: UInt32 = 0x1234_5678
    let val = ChecksumOptions.CRC32CValue(intVal)
    let expectedBase64 = Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString()
    #expect(val == .value(expectedBase64))
  }

  @Test func crc32cValueIntegerLiteral() {
    let val: ChecksumOptions.CRC32CValue = 0x1234_5678
    let expectedBase64 = Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString()
    #expect(val == .value(expectedBase64))

    // Verify full 32-bit unsigned integer range [0, UInt32.max] is preserved without truncation.
    let zero: ChecksumOptions.CRC32CValue = 0
    #expect(zero == .value(Data([0x00, 0x00, 0x00, 0x00]).base64EncodedString()))

    let maxVal: ChecksumOptions.CRC32CValue = 0xFFFF_FFFF
    #expect(maxVal == .value(Data([0xFF, 0xFF, 0xFF, 0xFF]).base64EncodedString()))
  }

  @Test func md5ValueAutoAndValue() {
    let auto = ChecksumOptions.MD5Value.auto
    let val = ChecksumOptions.MD5Value.value("test")

    #expect(auto != val)
    #expect(val == .value("test"))
  }

  @Test func md5ValueStringLiteral() {
    let val: ChecksumOptions.MD5Value = "my_md5_checksum"
    #expect(val == .value("my_md5_checksum"))
  }

  @Test func md5ValueDataInit() {
    // Verify 16-byte raw MD5 digest (matching ObjectChecksums.md5Hash) is Base64-encoded.
    let digest = Data((0..<16).map { UInt8($0) })
    let val = ChecksumOptions.MD5Value(digest)
    #expect(val == .value(digest.base64EncodedString()))

    let options = ChecksumOptions(crc32c: .init(0x1234_5678), md5: .init(digest))
    #expect(options.crc32c == .value(Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString()))
    #expect(options.md5 == .value(digest.base64EncodedString()))
  }
}
