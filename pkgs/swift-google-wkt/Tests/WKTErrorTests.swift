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
@testable import GoogleWKT
import Testing

@Suite struct WKTAnyErrorTests {
  @Test func mismatchedTypeURL() {
    let error = WKTAnyError.mismatchedTypeURL
    let anyError: any Error = error
    #expect(
      error.description
        == "The type URL of the message does not match the contents in the WKTAny."
    )
    #expect(
      error.debugDescription
        == "WKTAnyError.mismatchedTypeURL: The type URL of the message does not match the contents in the WKTAny."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func invalidNestedAnyType() {
    let error = WKTAnyError.invalidNestedAnyType
    let anyError: any Error = error
    #expect(
      error.description
        == "The @type field in a nested WKTAny is missing or invalid."
    )
    #expect(
      error.debugDescription
        == "WKTAnyError.invalidNestedAnyType: The @type field in a nested WKTAny is missing or invalid."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func missingValueField() {
    let error = WKTAnyError.missingValueField
    let anyError: any Error = error
    #expect(
      error.description
        == "The message is encoded as a JSON string but the 'value' field is missing."
    )
    #expect(
      error.debugDescription
        == "WKTAnyError.missingValueField: The message is encoded as a JSON string but the 'value' field is missing."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func invalidValueField() {
    let error = WKTAnyError.invalidValueField
    let anyError: any Error = error
    #expect(
      error.description
        == "The message is encoded as a JSON string but the 'value' field is not a string."
    )
    #expect(
      error.debugDescription
        == "WKTAnyError.invalidValueField: The message is encoded as a JSON string but the 'value' field is not a string."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func equatable() {
    #expect(WKTAnyError.mismatchedTypeURL == WKTAnyError.mismatchedTypeURL)
    #expect(WKTAnyError.mismatchedTypeURL != WKTAnyError.missingValueField)
  }
}

@Suite struct WKTDurationErrorTests {
  @Test func mismatchedSigns() {
    let error = WKTDurationError.mismatchedSigns
    let anyError: any Error = error
    #expect(
      error.description == "The seconds and nanosecond signs did not match."
    )
    #expect(
      error.debugDescription
        == "WKTDurationError.mismatchedSigns: The seconds and nanosecond signs did not match."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func outOfRange() {
    let error = WKTDurationError.outOfRange
    let anyError: any Error = error
    #expect(
      error.description
        == "The seconds or nanosecond components are out of range."
    )
    #expect(
      error.debugDescription
        == "WKTDurationError.outOfRange: The seconds or nanosecond components are out of range."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func invalidFormat() {
    let error = WKTDurationError.invalidFormat
    let anyError: any Error = error
    #expect(
      error.description
        == "Invalid format when parsing a duration from a string."
    )
    #expect(
      error.debugDescription
        == "WKTDurationError.invalidFormat: Invalid format when parsing a duration from a string."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func equatable() {
    #expect(WKTDurationError.mismatchedSigns == WKTDurationError.mismatchedSigns)
    #expect(WKTDurationError.mismatchedSigns != WKTDurationError.outOfRange)
  }
}

@Suite struct WKTTimestampErrorTests {
  @Test func outOfRange() {
    let error = WKTTimestampError.outOfRange
    let anyError: any Error = error
    #expect(
      error.description
        == "The seconds or nanosecond components are out of range."
    )
    #expect(
      error.debugDescription
        == "WKTTimestampError.outOfRange: The seconds or nanosecond components are out of range."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func invalidFormat() {
    let error = WKTTimestampError.invalidFormat
    let anyError: any Error = error
    #expect(
      error.description
        == "Invalid format when parsing a timestamp from a string."
    )
    #expect(
      error.debugDescription
        == "WKTTimestampError.invalidFormat: Invalid format when parsing a timestamp from a string."
    )
    #expect(String(reflecting: anyError) == error.debugDescription)
  }

  @Test func equatable() {
    #expect(WKTTimestampError.outOfRange == WKTTimestampError.outOfRange)
    #expect(WKTTimestampError.outOfRange != WKTTimestampError.invalidFormat)
  }
}
