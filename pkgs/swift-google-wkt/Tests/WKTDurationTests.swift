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
@_spi(GoogleCloudInternal) import GoogleWKT
import Testing

@Suite struct WKTDurationTests {
  @Test(
    "Duration initializer",
    arguments: [
      (Int64(123), Int32(456)),
      (Int64(-123), Int32(-456)),
      (Int64(123), Int32(0)),
      (Int64(-123), Int32(0)),
      (Int64(0), Int32(456)),
      (Int64(0), Int32(-456)),
    ])
  func initNormal(_ args: (Int64, Int32)) throws {
    let got = try GoogleWKT.WKTDuration(seconds: args.0, nanos: args.1)
    #expect(got.seconds == args.0)
    #expect(got.nanos == args.1)
  }

  @Test("Duration default nanos is 0")
  func defaultNanos() throws {
    let d = try GoogleWKT.WKTDuration(seconds: 42)
    #expect(d.seconds == 42)
    #expect(d.nanos == 0)
  }

  @Test(
    "Duration boundary nanos",
    arguments: [
      (Int64(1), GoogleWKT.WKTDuration.maxNanos),
      (Int64(-1), GoogleWKT.WKTDuration.minNanos),
    ])
  func boundaryNanos(_ args: (Int64, Int32)) throws {
    let d = try GoogleWKT.WKTDuration(seconds: args.0, nanos: args.1)
    #expect(d.seconds == args.0)
    #expect(d.nanos == args.1)
  }

  @Test(
    "Duration detect mismatched signs",
    arguments: [
      (Int64(123), Int32(-456)),
      (Int64(-123), Int32(456)),
    ])
  func mismatchedSigns(_ args: (Int64, Int32)) throws {
    #expect(throws: GoogleWKT.WKTDurationError.mismatchedSigns) {
      try GoogleWKT.WKTDuration(seconds: args.0, nanos: args.1)
    }
  }

  @Test(
    "Duration detect out of range seconds",
    arguments: [GoogleWKT.WKTDuration.maxSeconds + 1, GoogleWKT.WKTDuration.minSeconds - 1])
  func outOfRangeSeconds(_ seconds: Int64) throws {
    #expect(throws: GoogleWKT.WKTDurationError.outOfRange) {
      try GoogleWKT.WKTDuration(seconds: seconds, nanos: 0)
    }
  }

  @Test(
    "Duration detect out of range nanos",
    arguments: [Int32(1_000_000_000), Int32(-1_000_000_000)])
  func outOfRangeNanos(_ nanos: Int32) throws {
    #expect(throws: GoogleWKT.WKTDurationError.outOfRange) {
      try GoogleWKT.WKTDuration(seconds: 0, nanos: nanos)
    }
  }

  struct WrappedDuration: Encodable {
    let value: GoogleWKT.WKTDuration
  }

  @Test(
    "Duration JSON Encoding",
    arguments: [
      (Int64(1), Int32(0), "{\"value\":\"1s\"}"),
      (Int64(1), Int32(1000), "{\"value\":\"1.000001s\"}"),
      (Int64(1), Int32(1_000_000), "{\"value\":\"1.001s\"}"),
      (Int64(1), Int32(70_000_000), "{\"value\":\"1.070s\"}"),
      (Int64(1), Int32(70_000), "{\"value\":\"1.000070s\"}"),
      (Int64(1), Int32(70), "{\"value\":\"1.000000070s\"}"),
      (Int64(0), Int32(1), "{\"value\":\"0.000000001s\"}"),
      (Int64(-1), Int32(0), "{\"value\":\"-1s\"}"),
      (Int64(-1), Int32(-1_000_000), "{\"value\":\"-1.001s\"}"),
      (Int64(-1), Int32(-70_000_000), "{\"value\":\"-1.070s\"}"),
      (Int64(-1), Int32(-70_000), "{\"value\":\"-1.000070s\"}"),
      (Int64(-1), Int32(-70), "{\"value\":\"-1.000000070s\"}"),
      (Int64(0), Int32(-1_000_000), "{\"value\":\"-0.001s\"}"),
      (Int64(42), Int32(0), "{\"value\":\"42s\"}"),
      (Int64(-42), Int32(0), "{\"value\":\"-42s\"}"),
      (Int64(42), Int32(1_000_000), "{\"value\":\"42.001s\"}"),
      (Int64(-42), Int32(-1_000_000), "{\"value\":\"-42.001s\"}"),
      (Int64(315_576_000_000), Int32(0), "{\"value\":\"315576000000s\"}"),
      (Int64(-315_576_000_000), Int32(0), "{\"value\":\"-315576000000s\"}"),
      (Int64(315_576_000_000), Int32(999_999_999), "{\"value\":\"315576000000.999999999s\"}"),
      (Int64(-315_576_000_000), Int32(-999_999_999), "{\"value\":\"-315576000000.999999999s\"}"),
    ])
  func encodeJSON(_ args: (Int64, Int32, String)) throws {
    let duration = try GoogleWKT.WKTDuration(seconds: args.0, nanos: args.1)
    let wrapped = WrappedDuration(value: duration)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.2)
  }

  struct WrappedDurationDecode: Decodable {
    let value: GoogleWKT.WKTDuration
  }

  @Test(
    "Duration JSON Decoding",
    arguments: [
      ("{\"value\":\"1s\"}", Int64(1), Int32(0)),
      ("{\"value\":\"1.001s\"}", Int64(1), Int32(1_000_000)),
      ("{\"value\":\"1.070s\"}", Int64(1), Int32(70_000_000)),
      ("{\"value\":\"1.07s\"}", Int64(1), Int32(70_000_000)),
      ("{\"value\":\"1.1s\"}", Int64(1), Int32(100_000_000)),
      ("{\"value\":\"1.12s\"}", Int64(1), Int32(120_000_000)),
      ("{\"value\":\"1.1234s\"}", Int64(1), Int32(123_400_000)),
      ("{\"value\":\"1.12345s\"}", Int64(1), Int32(123_450_000)),
      ("{\"value\":\"1.1234567s\"}", Int64(1), Int32(123_456_700)),
      ("{\"value\":\"1.12345678s\"}", Int64(1), Int32(123_456_780)),
      ("{\"value\":\"0.000000001s\"}", Int64(0), Int32(1)),
      ("{\"value\":\"-1s\"}", Int64(-1), Int32(0)),
      ("{\"value\":\"-1.070s\"}", Int64(-1), Int32(-70_000_000)),
      ("{\"value\":\"-1.001s\"}", Int64(-1), Int32(-1_000_000)),
      ("{\"value\":\"-0.001s\"}", Int64(0), Int32(-1_000_000)),
      ("{\"value\":\"42s\"}", Int64(42), Int32(0)),
      ("{\"value\":\"-42s\"}", Int64(-42), Int32(0)),
      ("{\"value\":\"42.001s\"}", Int64(42), Int32(1_000_000)),
      ("{\"value\":\"-42.001s\"}", Int64(-42), Int32(-1_000_000)),
      ("{\"value\":\"315576000000s\"}", Int64(315_576_000_000), Int32(0)),
      ("{\"value\":\"-315576000000s\"}", Int64(-315_576_000_000), Int32(0)),
      ("{\"value\":\"315576000000.999999999s\"}", Int64(315_576_000_000), Int32(999_999_999)),
      ("{\"value\":\"-315576000000.999999999s\"}", Int64(-315_576_000_000), Int32(-999_999_999)),
    ])
  func decodeJSON(_ args: (String, Int64, Int32)) throws {
    let data = Data(args.0.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedDurationDecode.self, from: data)
    #expect(wrapped.value.seconds == args.1)
    #expect(wrapped.value.nanos == args.2)
  }

  @Test("Unpack Duration from Any")
  func durationAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Duration","value":"123.45s"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Duration")

    let got = try WKTDuration(fromAny: any)
    let want = try WKTDuration(seconds: 123, nanos: 450_000_000)
    #expect(got == want)
  }

  @Test func durationAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"123.45s"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) { let _ = try WKTDuration(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Duration into Any")
  func durationAnyPack() throws {
    let input = try WKTDuration(seconds: 123, nanos: 450_000_000)
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Duration","value":"123.450s"}}"#
    #expect(got == want)
  }
}
