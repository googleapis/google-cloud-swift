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
import Testing

@testable import GoogleCloudWkt

@Suite struct TimestampTests {
  @Test(
    "Timestamp detect out of range seconds",
    arguments: [
      GoogleCloudWkt.Timestamp.maxSeconds + 1,
      GoogleCloudWkt.Timestamp.minSeconds - 1,
    ])
  func outOfRangeSeconds(_ seconds: Int64) throws {
    #expect(throws: GoogleCloudWkt.TimestampError.outOfRange) {
      try GoogleCloudWkt.Timestamp(seconds: seconds, nanos: 0)
    }
  }

  @Test(
    "Timestamp parsing of known values",
    arguments: [
      ("0001-01-01T00:00:00Z", GoogleCloudWkt.Timestamp.minSeconds, 0),
      ("1970-01-01T00:00:00Z", 0, 0),
      ("1970-01-01T00:00:12Z", 12, 0),
      ("1970-01-01T00:00:12.34Z", 12, 340_000_000),
      ("1970-01-01T00:00:12.340Z", 12, 340_000_000),
      ("1970-01-01T00:00:12.345678912Z", 12, 345_678_912),
      ("1969-12-31T23:59:59Z", -1, 0),
      ("1969-12-31T23:59:48.123456789Z", -12, 123_456_789),
      ("9999-12-31T23:59:59Z", GoogleCloudWkt.Timestamp.maxSeconds, 0),
      ("1970-01-01T01:00:00+01:00", 0, 0),
      ("1970-01-01T00:00:00+01:00", -3600, 0),
      ("1969-12-31T23:00:00-01:00", 0, 0),
      ("1970-01-01T00:00:00-01:00", 3600, 0),
      ("1970-01-01T00:00:00+00:00", 0, 0),
      ("1970-01-01T00:00:00+05:30", -19800, 0),
    ])
  func fromString(input: String, wantSeconds: Int64, wantNanos: Int64) throws {
    let got = try Timestamp(fromString: input)
    #expect(got.seconds == wantSeconds)
    #expect(got.nanos == wantNanos)
  }

  // Verify timestamps can roundtrip from string -> struct -> string without loss.
  @Test(
    "Timestamp roundtrip from string",
    arguments: [
      "0001-01-01T00:00:00.123456789Z",
      "0001-01-01T00:00:00.123456Z",
      "0001-01-01T00:00:00.123Z",
      "0001-01-01T00:00:00Z",
      "1960-01-01T00:00:00.123456789Z",
      "1960-01-01T00:00:00.123456Z",
      "1960-01-01T00:00:00.123Z",
      "1960-01-01T00:00:00Z",
      "1970-01-01T00:00:00.123456789Z",
      "1970-01-01T00:00:00.123456Z",
      "1970-01-01T00:00:00.123Z",
      "1970-01-01T00:00:00Z",
      "9999-12-31T23:59:59.999999999Z",
      "9999-12-31T23:59:59.123456789Z",
      "9999-12-31T23:59:59.123456Z",
      "9999-12-31T23:59:59.123Z",
      "2026-04-21T12:34:56Z",
      "2026-04-21T12:34:56.789Z",
      "2026-04-21T12:34:56.789123456Z",
      "2000-02-29T00:00:00Z",
      "2000-02-29T23:59:59.999999999Z",
      "2024-02-29T12:00:00Z",
      "2024-02-29T12:00:00.000000001Z",
      "2400-02-29T00:00:00Z",
      "2024-02-28T23:59:59Z",
      "2024-03-01T00:00:00Z",
    ]
  )
  func roundtripString(_ input: String) throws {
    let ts = try GoogleCloudWkt.Timestamp(fromString: input)
    let formatted = ts.toString()
    #expect(input == formatted)
  }

  @Test(
    "Timestamp roundtrip from string with offset",
    arguments: [
      ("2000-02-29T00:00:00+05:00", "2000-02-28T19:00:00Z"),
      ("2000-02-29T00:00:00-01:00", "2000-02-29T01:00:00Z"),
      ("2024-02-29T12:00:00+00:30", "2024-02-29T11:30:00Z"),
      ("2026-04-21T12:00:00+08:00", "2026-04-21T04:00:00Z"),
      ("2026-04-21T12:00:00-07:00", "2026-04-21T19:00:00Z"),
      ("2026-04-21T00:00:00+01:00", "2026-04-20T23:00:00Z"),
      ("2026-04-21T23:00:00-02:00", "2026-04-22T01:00:00Z"),
      ("1970-01-01T00:00:00+01:00", "1969-12-31T23:00:00Z"),
    ]
  )
  func roundtripWithOffset(input: String, expected: String) throws {
    let ts = try GoogleCloudWkt.Timestamp(fromString: input)
    let formatted = ts.toString()
    #expect(formatted == expected)
  }

  @Test(
    "Timestamp detect invalid format",
    arguments: [
      "",  // Too short
      "2024-00-01T00:00:00Z",  // Month 00
      "2024-20-01T00:00:00Z",  // Month 20
      "2024-01-01T25:00:00Z",  // Hour 25
      "2024-01-01T00:60:00Z",  // Minute 60
      "2024-01-01T00:00:62Z",  // Second 62
      "2024-01-01T00:00:00+25:00",  // Offset hour 25
      "2024-01-01T00:00:00+00:60",  // Offset minute 60
      "2024-01-01T00:00:00+EST",  // Invalid offset
      "2024/06/04T00:00:00Z",  // Invalid date separator
      "2024-06-04T12.34:56Z",  // Invalid time separator
      "2024-06-04 12:34:56Z",  // Missing 'T' separator (space)
      "2024-06-04_12:34:56Z",  // Invalid date/time separator (underscore)
      "2025-02-29T00:00:00Z",  // Feb 29 on non-leap year
      "2026-04-31T00:00:00Z",  // April 31
      "2024-06-31T00:00:00Z",  // June 31
      "2024-09-31T00:00:00Z",  // Sept 31
      "2024-11-31T00:00:00Z",  // Nov 31
      "2024-02-30T00:00:00Z",  // Feb 30
    ]
  )
  func invalidFormat(_ input: String) throws {
    #expect(throws: TimestampError.invalidFormat) {
      try Timestamp(fromString: input)
    }
  }

  @Test("Unpack Timestamp from Any")
  func timestampAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2026-04-21T12:34:56.789123456Z"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Timestamp")

    let got = try Timestamp(fromAny: any)
    let want = try Timestamp(fromString: "2026-04-21T12:34:56.789123456Z")
    #expect(got == want)
  }

  @Test func timestampAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"2026-04-21T12:34:56.789123456Z"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try Timestamp(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Timestamp into Any")
  func timestampAnyPack() throws {
    let input = try Timestamp(fromString: "2026-04-21T12:34:56.789123456Z")
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2026-04-21T12:34:56.789123456Z"}}"#
    #expect(got == want)
  }

  @Test(
    "Timestamp JSON Encoding",
    arguments: [
      (0, 0, "{\"value\":\"1970-01-01T00:00:00Z\"}"),
      (12, 340_000_000, "{\"value\":\"1970-01-01T00:00:12.340Z\"}"),
      (12, 345_678_912, "{\"value\":\"1970-01-01T00:00:12.345678912Z\"}"),
      (-1, 0, "{\"value\":\"1969-12-31T23:59:59Z\"}"),
      (GoogleCloudWkt.Timestamp.minSeconds, 0, "{\"value\":\"0001-01-01T00:00:00Z\"}"),
    ]
  )
  func encodeJSON(_ args: (Int64, Int64, String)) throws {
    let ts = try Timestamp(seconds: args.0, nanos: args.1)
    let wrapped = WrappedTimestamp(value: ts)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.2)
  }

  @Test(
    "Timestamp JSON Decoding",
    arguments: [
      ("{\"value\":\"1970-01-01T00:00:00Z\"}", 0, 0),
      ("{\"value\":\"1970-01-01T00:00:12.34Z\"}", 12, 340_000_000),
      ("{\"value\":\"1970-01-01T00:00:12.345678912Z\"}", 12, 345_678_912),
      ("{\"value\":\"1969-12-31T23:59:59Z\"}", -1, 0),
      ("{\"value\":\"0001-01-01T00:00:00Z\"}", GoogleCloudWkt.Timestamp.minSeconds, 0),
      ("{\"value\":\"1970-01-01T01:00:00+01:00\"}", 0, 0),
    ]
  )
  func decodeJSON(_ args: (String, Int64, Int64)) throws {
    let data = Data(args.0.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedTimestampDecode.self, from: data)
    #expect(wrapped.value.seconds == args.1)
    #expect(wrapped.value.nanos == args.2)
  }
}

struct WrappedTimestamp: Encodable {
  let value: Timestamp
}

struct WrappedTimestampDecode: Decodable {
  let value: Timestamp
}
