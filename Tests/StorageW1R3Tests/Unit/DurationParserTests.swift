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

@Suite struct DurationParserTests {
  @Test func parsesMilliseconds() throws {
    #expect(try DurationParser.parse("500ms") == .milliseconds(500))
    #expect(try DurationParser.parse("0ms") == .milliseconds(0))
    #expect(try DurationParser.parse("1500.5ms") == .milliseconds(1500.5))
  }

  @Test func parsesSeconds() throws {
    #expect(try DurationParser.parse("30s") == .seconds(30))
    #expect(try DurationParser.parse("0s") == .seconds(0))
    #expect(try DurationParser.parse("2.5s") == .seconds(2.5))
    #expect(try DurationParser.parse("42") == .seconds(42))
    #expect(try DurationParser.parse("  10  ") == .seconds(10))
  }

  @Test func parsesMinutes() throws {
    #expect(try DurationParser.parse("5m") == .seconds(300))
    #expect(try DurationParser.parse("1.5m") == .seconds(90))
  }

  @Test func parsesHours() throws {
    #expect(try DurationParser.parse("1h") == .seconds(3600))
    #expect(try DurationParser.parse("0.5h") == .seconds(1800))
  }

  @Test func rejectsInvalidInputs() {
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("")
    }
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("   ")
    }
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("-5s")
    }
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("-100ms")
    }
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("invalid")
    }
    #expect(throws: ValidationError.self) {
      try DurationParser.parse("10d")
    }
  }
}
