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

import ArgumentParser
@testable import StorageW1R3
import Testing

@Suite struct SizeParserTests {
  @Test func parsesPlainNumbers() throws {
    #expect(try SizeParser.parse("0") == 0)
    #expect(try SizeParser.parse("1024") == 1024)
    #expect(try SizeParser.parse("  42  ") == 42)
  }

  @Test func parsesBinaryUnits() throws {
    #expect(try SizeParser.parse("1k") == 1024)
    #expect(try SizeParser.parse("128KiB") == 128 * 1024)
    #expect(try SizeParser.parse("1MiB") == 1024 * 1024)
    #expect(try SizeParser.parse("1m") == 1024 * 1024)
    #expect(try SizeParser.parse("1GiB") == 1024 * 1024 * 1024)
    #expect(try SizeParser.parse("1g") == 1024 * 1024 * 1024)
    #expect(try SizeParser.parse("1TiB") == 1024 * 1024 * 1024 * 1024)
  }

  @Test func parsesDecimalUnits() throws {
    #expect(try SizeParser.parse("1b") == 1)
    #expect(try SizeParser.parse("1kb") == 1000)
    #expect(try SizeParser.parse("1mb") == 1000 * 1000)
    #expect(try SizeParser.parse("1gb") == 1000 * 1000 * 1000)
    #expect(try SizeParser.parse("1tb") == 1000 * 1000 * 1000 * 1000)
  }

  @Test func parsesFractionalUnits() throws {
    #expect(try SizeParser.parse("1.5KiB") == 1536)
    #expect(try SizeParser.parse("0.5MiB") == 512 * 1024)
  }

  @Test func rejectsInvalidInputs() {
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("")
    }
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("   ")
    }
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("-1")
    }
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("-10KiB")
    }
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("invalid")
    }
    #expect(throws: ValidationError.self) {
      try SizeParser.parse("100xyz")
    }
  }
}
