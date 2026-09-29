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

import StorageW1R3
import Testing

@Suite struct Crc32cOptionTests {
  @Test func parsesAlwaysVariants() {
    #expect(Crc32cOption(argument: "always") == .always)
    #expect(Crc32cOption(argument: "ALWAYS") == .always)
    #expect(Crc32cOption(argument: "enabled") == .always)
    #expect(Crc32cOption(argument: "Enabled") == .always)
    #expect(Crc32cOption(argument: "true") == .always)
    #expect(Crc32cOption(argument: "TRUE") == .always)
  }

  @Test func parsesNeverVariants() {
    #expect(Crc32cOption(argument: "never") == .never)
    #expect(Crc32cOption(argument: "NEVER") == .never)
    #expect(Crc32cOption(argument: "disabled") == .never)
    #expect(Crc32cOption(argument: "Disabled") == .never)
    #expect(Crc32cOption(argument: "false") == .never)
    #expect(Crc32cOption(argument: "FALSE") == .never)
  }

  @Test func parsesRandomVariants() {
    #expect(Crc32cOption(argument: "random") == .random)
    #expect(Crc32cOption(argument: "RANDOM") == .random)
  }

  @Test func rejectsInvalidArguments() {
    #expect(Crc32cOption(argument: "") == nil)
    #expect(Crc32cOption(argument: "sometimes") == nil)
    #expect(Crc32cOption(argument: "1") == nil)
  }
}
