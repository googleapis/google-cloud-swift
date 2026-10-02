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
    #expect(
      error.description
        == "The type URL of the message does not match the contents in the WKTAny."
    )
    #expect(error.debugDescription == "WKTAnyError.mismatchedTypeURL")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The caller attempted to extract a message from the WKTAny that has a different type URL from the contents of the Any itself."
    )
  }

  @Test func invalidNestedAnyType() {
    let error = WKTAnyError.invalidNestedAnyType
    #expect(
      error.description
        == "The @type field in a nested WKTAny is missing or invalid."
    )
    #expect(error.debugDescription == "WKTAnyError.invalidNestedAnyType")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The nested @type field for the inner WKTAny contents was missing or was not a JSON string."
    )
  }

  @Test func missingValueField() {
    let error = WKTAnyError.missingValueField
    #expect(
      error.description
        == "The message is encoded as a JSON string but the 'value' field is missing."
    )
    #expect(error.debugDescription == "WKTAnyError.missingValueField")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason == "The 'value' field is missing from the JSON object."
    )
  }

  @Test func invalidValueField() {
    let error = WKTAnyError.invalidValueField
    #expect(
      error.description
        == "The message is encoded as a JSON string but the 'value' field is not a string."
    )
    #expect(error.debugDescription == "WKTAnyError.invalidValueField")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The 'value' field is present, but it is not of string type."
    )
  }

  @Test func equatable() {
    #expect(WKTAnyError.mismatchedTypeURL == WKTAnyError.mismatchedTypeURL)
    #expect(WKTAnyError.mismatchedTypeURL != WKTAnyError.missingValueField)
  }
}

@Suite struct WKTDurationErrorTests {
  @Test func mismatchedSigns() {
    let error = WKTDurationError.mismatchedSigns
    #expect(
      error.description == "The seconds and nanosecond signs did not match."
    )
    #expect(error.debugDescription == "WKTDurationError.mismatchedSigns")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The seconds and nanoseconds components of the duration must have the same sign."
    )
  }

  @Test func outOfRange() {
    let error = WKTDurationError.outOfRange
    #expect(
      error.description
        == "The seconds or nanosecond components are out of range."
    )
    #expect(error.debugDescription == "WKTDurationError.outOfRange")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The duration values exceed the allowed range of approximately ±10,000 years."
    )
  }

  @Test func invalidFormat() {
    let error = WKTDurationError.invalidFormat
    #expect(
      error.description
        == "Invalid format when parsing a duration from a string."
    )
    #expect(error.debugDescription == "WKTDurationError.invalidFormat")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The duration string could not be parsed into valid seconds and nanoseconds."
    )
  }

  @Test func equatable() {
    #expect(WKTDurationError.mismatchedSigns == WKTDurationError.mismatchedSigns)
    #expect(WKTDurationError.mismatchedSigns != WKTDurationError.outOfRange)
  }
}

@Suite struct WKTTimestampErrorTests {
  @Test func outOfRange() {
    let error = WKTTimestampError.outOfRange
    #expect(
      error.description
        == "The seconds or nanosecond components are out of range."
    )
    #expect(error.debugDescription == "WKTTimestampError.outOfRange")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The timestamp values exceed the allowed range (0001-01-01T00:00:00Z to 9999-12-31T23:59:59.999999999Z)."
    )
  }

  @Test func invalidFormat() {
    let error = WKTTimestampError.invalidFormat
    #expect(
      error.description
        == "Invalid format when parsing a timestamp from a string."
    )
    #expect(error.debugDescription == "WKTTimestampError.invalidFormat")
    #expect(error.localizedDescription == error.description)
    #expect(
      error.failureReason
        == "The timestamp string could not be parsed as a valid RFC 3339 date-time format."
    )
  }

  @Test func equatable() {
    #expect(WKTTimestampError.outOfRange == WKTTimestampError.outOfRange)
    #expect(WKTTimestampError.outOfRange != WKTTimestampError.invalidFormat)
  }
}
