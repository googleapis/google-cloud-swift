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

  @Test func noneOptions() {
    let options = ChecksumOptions.none
    #expect(options.crc32c == nil)
    #expect(options.md5 == nil)
  }

  @Test func customInitialization() {
    let options = ChecksumOptions(crc32c: "crc_base64", md5: "md5_base64")
    #expect(options.crc32c == .value("crc_base64"))
    #expect(options.md5 == .value("md5_base64"))
  }

  @Test func checksumValueAutoAndValue() {
    let auto = ChecksumOptions.ChecksumValue.auto
    let val = ChecksumOptions.ChecksumValue.value("test")

    #expect(auto != val)
    #expect(val == .value("test"))
  }

  @Test func checksumValueStringLiteral() {
    let val: ChecksumOptions.ChecksumValue = "my_checksum"
    #expect(val == .value("my_checksum"))
  }

  @Test func checksumValueUInt32Init() {
    let intVal: UInt32 = 0x1234_5678
    let val = ChecksumOptions.ChecksumValue(intVal)
    let expectedBase64 = Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString()
    #expect(val == .value(expectedBase64))
  }

  @Test func checksumValueIntegerLiteral() {
    let val: ChecksumOptions.ChecksumValue = 0x1234_5678
    let expectedBase64 = Data([0x12, 0x34, 0x56, 0x78]).base64EncodedString()
    #expect(val == .value(expectedBase64))
  }
}
