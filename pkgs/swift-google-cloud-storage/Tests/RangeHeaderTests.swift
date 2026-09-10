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
// See the License for theing specific language governing permissions and
// limitations under the License.

import Foundation
@testable import GoogleCloudStorage
import Testing

@Suite struct RangeHeaderTests {
  @Test(arguments: [
    ("bytes=0-1999", HttpRange(start: 0, end: 1999)),
    ("bytes=2000-", HttpRange(start: 2000, end: nil)),
    ("bytes=-2000", HttpRange(start: nil, end: 2000)),
  ])
  func parseRangeHeader(header: String, expected: HttpRange) throws {
    let parsed = try HttpRange.parse(header)
    #expect(parsed == expected)
  }

  @Test(arguments: [
    "foo=0-1999",
    "bytes=abc-def",
    "bytes=-",
    "bytes=2000-1000",
  ])
  func parseRangeHeaderInvalid(header: String) {
    #expect(throws: UploadError.self) {
      _ = try HttpRange.parse(header)
    }
  }

  @Test(arguments: [
    ("bytes=0-1999", UInt64(2000)),
    ("bytes=-2000", UInt64(2001)),
  ])
  func parseNextRangeStart(header: String, expectedNextStart: UInt64) throws {
    let nextStart = try HttpRange.parseNextRangeStart(header)
    #expect(nextStart == expectedNextStart)
  }

  @Test(arguments: [
    "bytes=2000-",
    "bytes=abc-def",
  ])
  func parseNextRangeStartInvalid(header: String) {
    #expect(throws: UploadError.self) {
      _ = try HttpRange.parseNextRangeStart(header)
    }
  }

  @Test(arguments: [
    ("bytes 0-1999/5000", HttpContentRange(start: 0, end: 1999, totalSize: 5000)),
    ("bytes 100-200/*", HttpContentRange(start: 100, end: 200, totalSize: nil)),
  ])
  func parseContentRangeHeader(header: String, expected: HttpContentRange) throws {
    let parsed = try HttpContentRange.parse(header)
    #expect(parsed == expected)
  }

  @Test(arguments: [
    "bytes */5000",
    "invalid",
    "bytes 200-100/5000",
    "bytes 0-1999/abc",
    "foo 0-1999/5000",
  ])
  func parseContentRangeHeaderInvalid(header: String) {
    #expect(throws: DownloadError.self) {
      _ = try HttpContentRange.parse(header)
    }
  }
}
