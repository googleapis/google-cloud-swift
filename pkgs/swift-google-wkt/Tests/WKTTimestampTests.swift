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
@_spi(GoogleCloudInternal) @testable import GoogleWKT
import Testing

@Suite struct WKTTimestampTests {
  struct WrappedTimestamp: Codable {
    let value: WKTTimestamp
  }

  @Test(
    "Timestamp detect out of range seconds",
    arguments: [
      WKTTimestamp.maxSeconds + 1,
      WKTTimestamp.minSeconds - 1,
    ])
  func outOfRangeSeconds(_ seconds: Int64) throws {
    #expect(throws: WKTTimestampError.outOfRange) {
      try WKTTimestamp(seconds: seconds, nanos: 0)
    }
  }

  @Test(
    "Timestamp detect out of range nanos",
    arguments: [
      -1,
      1_000_000_000,
    ])
  func outOfRangeNanos(_ nanos: Int32) throws {
    #expect(throws: WKTTimestampError.outOfRange) {
      try WKTTimestamp(seconds: 0, nanos: nanos)
    }
  }

  @Test("Timestamp default nanos is 0")
  func defaultNanos() throws {
    let ts = try WKTTimestamp(seconds: 12345)
    #expect(ts.seconds == 12345)
    #expect(ts.nanos == 0)
  }

  @Test(
    "Timestamp boundary nanos",
    arguments: [
      WKTTimestamp.minNanos,
      WKTTimestamp.maxNanos,
    ])
  func boundaryNanos(_ nanos: Int32) throws {
    let ts = try WKTTimestamp(seconds: 0, nanos: nanos)
    #expect(ts.seconds == 0)
    #expect(ts.nanos == nanos)
  }

  @Test(
    "Timestamp parsing of known values",
    arguments: [
      ("0001-01-01T00:00:00Z", WKTTimestamp.minSeconds, Int32(0)),
      ("1970-01-01T00:00:00Z", 0, Int32(0)),
      ("1970-01-01T00:00:12Z", 12, Int32(0)),
      ("1970-01-01T00:00:12.34Z", 12, Int32(340_000_000)),
      ("1970-01-01T00:00:12.340Z", 12, Int32(340_000_000)),
      ("1970-01-01T00:00:12.345678912Z", 12, Int32(345_678_912)),
      ("1969-12-31T23:59:59Z", -1, Int32(0)),
      ("1969-12-31T23:59:48.123456789Z", -12, Int32(123_456_789)),
      ("9999-12-31T23:59:59Z", WKTTimestamp.maxSeconds, Int32(0)),
      ("1970-01-01T01:00:00+01:00", 0, Int32(0)),
      ("1970-01-01T00:00:00+01:00", -3600, Int32(0)),
      ("1969-12-31T23:00:00-01:00", 0, Int32(0)),
      ("1970-01-01T00:00:00-01:00", 3600, Int32(0)),
      ("1970-01-01T00:00:00+00:00", 0, Int32(0)),
      ("1970-01-01T00:00:00+05:30", -19800, Int32(0)),
    ])
  func fromString(input: String, wantSeconds: Int64, wantNanos: Int32) throws {
    let got = try WKTTimestamp(fromString: input)
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
    let ts = try WKTTimestamp(fromString: input)
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
    let ts = try WKTTimestamp(fromString: input)
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
      "2026-01-01T00:00:00.1234567899Z",  // >9 fractional digits
      "1970-01-01T00:00:00.0000000000Z",  // 10 fractional digits
      "2026-01-01T00:00:00.Z",  // Empty fractional segment
      "1970-01-01T00:00:00+01ab",  // Non-numeric offset minutes
      "1970-01-01T00:00:00+0:1:0:0",  // Malformed colons in offset
      "2024-+1-01T00:00:00Z",  // Signed month
      "2024-01-01T-0:00:00Z",  // Signed hour
    ]
  )
  func invalidFormat(_ input: String) throws {
    #expect(throws: WKTTimestampError.invalidFormat) {
      try WKTTimestamp(fromString: input)
    }
  }

  @Test("Unpack Timestamp from Any")
  func timestampAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2026-04-21T12:34:56.789123456Z"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeURL == "type.googleapis.com/google.protobuf.Timestamp")

    let got = try WKTTimestamp(fromAny: any)
    let want = try WKTTimestamp(fromString: "2026-04-21T12:34:56.789123456Z")
    #expect(got == want)
  }

  @Test func timestampAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"2026-04-21T12:34:56.789123456Z"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTTimestamp(fromAny: any)
    }
    #expect(error == .mismatchedTypeURL)
  }

  @Test func timestampAnyUnpackMissingValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Timestamp"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(throws: WKTAnyError.missingValueField) {
      let _ = try WKTTimestamp(fromAny: any)
    }
  }

  @Test func timestampAnyUnpackInvalidValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":123}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(throws: WKTAnyError.invalidValueField) {
      let _ = try WKTTimestamp(fromAny: any)
    }
  }

  @Test("Pack Timestamp into Any")
  func timestampAnyPack() throws {
    let input = try WKTTimestamp(fromString: "2026-04-21T12:34:56.789123456Z")
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
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
      (0, Int32(0), "{\"value\":\"1970-01-01T00:00:00Z\"}"),
      (12, Int32(340_000_000), "{\"value\":\"1970-01-01T00:00:12.340Z\"}"),
      (12, Int32(345_678_912), "{\"value\":\"1970-01-01T00:00:12.345678912Z\"}"),
      (-1, Int32(0), "{\"value\":\"1969-12-31T23:59:59Z\"}"),
      (WKTTimestamp.minSeconds, Int32(0), "{\"value\":\"0001-01-01T00:00:00Z\"}"),
    ]
  )
  func encodeJSON(_ args: (Int64, Int32, String)) throws {
    let ts = try WKTTimestamp(seconds: args.0, nanos: args.1)
    let wrapped = WrappedTimestamp(value: ts)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.2)
  }

  @Test(
    "Timestamp JSON Decoding",
    arguments: [
      ("{\"value\":\"1970-01-01T00:00:00Z\"}", 0, Int32(0)),
      ("{\"value\":\"1970-01-01T00:00:12.34Z\"}", 12, Int32(340_000_000)),
      ("{\"value\":\"1970-01-01T00:00:12.345678912Z\"}", 12, Int32(345_678_912)),
      ("{\"value\":\"1969-12-31T23:59:59Z\"}", -1, Int32(0)),
      ("{\"value\":\"0001-01-01T00:00:00Z\"}", WKTTimestamp.minSeconds, Int32(0)),
      ("{\"value\":\"1970-01-01T01:00:00+01:00\"}", 0, Int32(0)),
    ]
  )
  func decodeJSON(_ args: (String, Int64, Int32)) throws {
    let data = Data(args.0.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedTimestamp.self, from: data)
    #expect(wrapped.value.seconds == args.1)
    #expect(wrapped.value.nanos == args.2)
  }

  @Test("Timestamp Comparable")
  func comparable() throws {
    let t1 = try WKTTimestamp(seconds: -10, nanos: 0)
    let t2 = try WKTTimestamp(seconds: -10, nanos: 500)
    let t3 = try WKTTimestamp(seconds: -9, nanos: 0)
    let t4 = try WKTTimestamp(seconds: 0, nanos: 0)
    let t5 = try WKTTimestamp(seconds: 0, nanos: 1)
    let t6 = try WKTTimestamp(seconds: 10, nanos: 100)
    let t7 = try WKTTimestamp(seconds: 10, nanos: 200)
    let t8 = try WKTTimestamp(seconds: 20, nanos: 0)

    #expect(t1 < t2)
    #expect(t2 < t3)
    #expect(t3 < t4)
    #expect(t4 < t5)
    #expect(t5 < t6)
    #expect(t6 < t7)
    #expect(t7 < t8)

    #expect(t8 > t7)
    #expect(t7 >= t6)
    #expect(t1 <= t2)
    #expect(t1 <= t1)
    #expect(t1 >= t1)
    #expect(!(t1 < t1))
    #expect(!(t1 > t1))

    let unsorted = [t6, t1, t8, t3, t7, t4, t2, t5]
    let sorted = unsorted.sorted()
    #expect(sorted == [t1, t2, t3, t4, t5, t6, t7, t8])

    let range = t2...t7
    #expect(!range.contains(t1))
    #expect(range.contains(t2))
    #expect(range.contains(t5))
    #expect(range.contains(t7))
    #expect(!range.contains(t8))
  }

  @Test("Timestamp Hashable")
  func hashable() throws {
    let t1 = try WKTTimestamp(seconds: 1234, nanos: 5678)
    let t2 = try WKTTimestamp(seconds: 1234, nanos: 5678)
    let t3 = try WKTTimestamp(seconds: 1234, nanos: 9999)
    let t4 = try WKTTimestamp(seconds: 5678, nanos: 5678)

    #expect(t1 == t2)
    #expect(t1.hashValue == t2.hashValue)

    var set: Set<WKTTimestamp> = []
    set.insert(t1)
    set.insert(t2)
    set.insert(t3)
    set.insert(t4)
    #expect(set.count == 3)
    #expect(set.contains(t1))
    #expect(set.contains(t3))
    #expect(set.contains(t4))

    var dict: [WKTTimestamp: String] = [:]
    dict[t1] = "first"
    dict[t2] = "second"
    dict[t3] = "third"
    #expect(dict.count == 2)
    #expect(dict[t1] == "second")
    #expect(dict[t3] == "third")
  }

  @Test(
    "Timestamp clampingSeconds",
    arguments: [
      (Int64(0), Int32(0), Int64(0), Int32(0)),
      (Int64(12345), Int32(0), Int64(12345), Int32(0)),
      (Int64(0), Int32(1_234_567_890), Int64(1), Int32(234_567_890)),
      (Int64(0), Int32(2_100_000_123), Int64(2), Int32(100_000_123)),
      (Int64(0), Int32(-1_400_000_000), Int64(-2), Int32(600_000_000)),
      (Int64(0), Int32(-2_100_000_000), Int64(-3), Int32(900_000_000)),
      (Int64(0), Int32(-1_000_000_000), Int64(-1), Int32(0)),
      (Int64(0), Int32(-2_000_000_000), Int64(-2), Int32(0)),
      (
        WKTTimestamp.minSeconds,
        WKTTimestamp.minNanos,
        WKTTimestamp.minSeconds,
        WKTTimestamp.minNanos
      ),
      (
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos,
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos
      ),
      (
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos + 1,
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos
      ),
      (
        WKTTimestamp.maxSeconds + 1,
        Int32(-1_000_000_000),
        WKTTimestamp.maxSeconds,
        Int32(0)
      ),
      (
        WKTTimestamp.minSeconds - 1,
        Int32(1_000_000_000),
        WKTTimestamp.minSeconds,
        Int32(0)
      ),
      (
        WKTTimestamp.maxSeconds + 1,
        Int32(0),
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos
      ),
      (
        WKTTimestamp.minSeconds - 1,
        Int32(0),
        WKTTimestamp.minSeconds,
        WKTTimestamp.minNanos
      ),
      (
        WKTTimestamp.maxSeconds - 1,
        Int32(2_000_000_001),
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos
      ),
      (
        WKTTimestamp.minSeconds + 1,
        Int32(-1_500_000_000),
        WKTTimestamp.minSeconds,
        WKTTimestamp.minNanos
      ),
      (
        Int64.max,
        Int32.max,
        WKTTimestamp.maxSeconds,
        WKTTimestamp.maxNanos
      ),
      (
        Int64.min,
        Int32.min,
        WKTTimestamp.minSeconds,
        WKTTimestamp.minNanos
      ),
    ]
  )
  func clampingSeconds(_ args: (Int64, Int32, Int64, Int32)) {
    let got = WKTTimestamp(clampingSeconds: args.0, nanos: args.1)
    #expect(got.seconds == args.2)
    #expect(got.nanos == args.3)
  }

  @Test("Timestamp clampingSeconds default nanos is 0")
  func clampingSecondsDefaultNanos() {
    let got = WKTTimestamp(clampingSeconds: 42)
    #expect(got.seconds == 42)
    #expect(got.nanos == 0)
  }

  @Test(
    "Timestamp Date conversion",
    arguments: [
      (Int64(0), Int32(0), TimeInterval(0)),
      (Int64(1_700_000_000), Int32(500_000_000), TimeInterval(1_700_000_000.5)),
      (Int64(-1), Int32(0), TimeInterval(-1.0)),
      (Int64(-1), Int32(250_000_000), TimeInterval(-0.75)),
      (Int64(-12), Int32(500_000_000), TimeInterval(-11.5)),
      (Int64(12345), Int32(125_000_000), TimeInterval(12345.125)),
    ]
  )
  func dateConversion(_ args: (Int64, Int32, TimeInterval)) throws {
    let date = Date(timeIntervalSince1970: args.2)
    let ts = WKTTimestamp(date)

    #expect(ts.seconds == args.0)
    #expect(ts.nanos == args.1)
    #expect(ts.timeIntervalSince1970 == args.2)
    #expect(ts.date == date)
  }

  @Test("Timestamp Date boundary clamping")
  func dateBoundaryClamping() {
    let distantPast = WKTTimestamp(Date.distantPast)
    #expect(distantPast.seconds == WKTTimestamp.minSeconds)
    #expect(distantPast.nanos == WKTTimestamp.minNanos)

    let exactMin = WKTTimestamp(
      Date(timeIntervalSince1970: TimeInterval(WKTTimestamp.minSeconds)))
    #expect(exactMin.seconds == WKTTimestamp.minSeconds)
    #expect(exactMin.nanos == WKTTimestamp.minNanos)

    let exactMaxPlusOne = WKTTimestamp(
      Date(timeIntervalSince1970: TimeInterval(WKTTimestamp.maxSeconds) + 1.0))
    #expect(exactMaxPlusOne.seconds == WKTTimestamp.maxSeconds)
    #expect(exactMaxPlusOne.nanos == WKTTimestamp.maxNanos)

    let beforeMin = WKTTimestamp(
      Date(timeIntervalSince1970: TimeInterval(WKTTimestamp.minSeconds) - 10_000))
    #expect(beforeMin.seconds == WKTTimestamp.minSeconds)
    #expect(beforeMin.nanos == WKTTimestamp.minNanos)

    let afterMax = WKTTimestamp(
      Date(timeIntervalSince1970: TimeInterval(WKTTimestamp.maxSeconds) + 10_000))
    #expect(afterMax.seconds == WKTTimestamp.maxSeconds)
    #expect(afterMax.nanos == WKTTimestamp.maxNanos)

    let nanDate = WKTTimestamp(Date(timeIntervalSince1970: .nan))
    #expect(nanDate.seconds == 0)
    #expect(nanDate.nanos == 0)

    let posInf = WKTTimestamp(Date(timeIntervalSince1970: .infinity))
    #expect(posInf.seconds == WKTTimestamp.maxSeconds)
    #expect(posInf.nanos == WKTTimestamp.maxNanos)

    let negInf = WKTTimestamp(Date(timeIntervalSince1970: -.infinity))
    #expect(negInf.seconds == WKTTimestamp.minSeconds)
    #expect(negInf.nanos == WKTTimestamp.minNanos)
  }

  @Test("Timestamp now")
  func timestampNow() {
    let before = WKTTimestamp(Date().addingTimeInterval(-10))
    let now = WKTTimestamp.now
    let after = WKTTimestamp(Date().addingTimeInterval(10))
    #expect(now >= before)
    #expect(now <= after)
  }

  @Test(
    "Timestamp init?(rfc3339:) valid",
    arguments: [
      ("1970-01-01T00:00:00Z", Int64(0), Int32(0)),
      ("2026-04-21T12:34:56.789123456Z", Int64(1_776_774_896), Int32(789_123_456)),
      ("1970-01-01T01:00:00+01:00", Int64(0), Int32(0)),
    ]
  )
  func initRFC3339Valid(_ args: (String, Int64, Int32)) throws {
    let ts = try #require(WKTTimestamp(rfc3339: args.0))
    #expect(ts.seconds == args.1)
    #expect(ts.nanos == args.2)
  }

  @Test(
    "Timestamp init?(rfc3339:) invalid",
    arguments: [
      "",
      "invalid",
      "0000-01-01T00:00:00Z",
      "10000-01-01T00:00:00Z",
      "2025-02-29T00:00:00Z",
    ]
  )
  func initRFC3339Invalid(_ input: String) {
    #expect(WKTTimestamp(rfc3339: input) == nil)
  }

  @Test(
    "Timestamp CustomStringConvertible description",
    arguments: [
      (Int64(0), Int32(0), "1970-01-01T00:00:00Z"),
      (Int64(12), Int32(340_000_000), "1970-01-01T00:00:12.340Z"),
      (Int64(12), Int32(345_678_912), "1970-01-01T00:00:12.345678912Z"),
      (WKTTimestamp.minSeconds, Int32(0), "0001-01-01T00:00:00Z"),
    ]
  )
  func customStringConvertible(_ args: (Int64, Int32, String)) throws {
    let ts = try WKTTimestamp(seconds: args.0, nanos: args.1)
    #expect(ts.description == args.2)
    #expect("\(ts)" == args.2)
  }
}
