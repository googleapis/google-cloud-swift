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

@Suite struct WKTInt64ValueTests {
  struct WrappedInt64ValueEncode: Encodable {
    let value: GoogleWKT.WKTInt64Value?
  }

  @Test(
    "Int64Value JSON Encoding",
    arguments: [
      (123, "{\"value\":\"123\"}"),
      (0, "{\"value\":\"0\"}"),
    ])
  func encodeJSON(_ args: (Int64, String)) throws {
    let wrapped = WrappedInt64ValueEncode(value: args.0)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("Int64Value JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedInt64ValueEncode(value: nil)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedInt64ValueDecode: Decodable {
    let value: GoogleWKT.WKTInt64Value?
  }

  @Test(
    "Int64Value JSON Decoding",
    arguments: [
      ("{\"value\":\"123\"}", 123),
      ("{\"value\":\"0\"}", 0),
      ("{\"value\":123}", 123),
      ("{\"value\":0}", 0),
    ])
  func decodeJSON(_ args: (String, Int64)) throws {
    let data = Data(args.0.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedInt64ValueDecode.self, from: data)
    #expect(wrapped.value == args.1)
  }

  @Test("Int64Value JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedInt64ValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleWKT.WKTAny
  }

  @Test("Unpack Int64Value from Any with string")
  func int64ValueAnyUnpackString() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"123"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTInt64ValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Int64Value")

    let got = try WKTInt64Value(fromAny: any)
    let want = Int64(123)
    #expect(got == want)
  }

  @Test("Unpack Int64Value from Any with number")
  func int64ValueAnyUnpackNumber() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":123}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTInt64ValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Int64Value")

    let got = try WKTInt64Value(fromAny: any)
    let want = Int64(123)
    #expect(got == want)
  }

  @Test func int64ValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"123"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTInt64ValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) { let _ = try WKTInt64Value(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Int64Value into Any")
  func int64ValueAnyPack() throws {
    let input = WKTInt64Value(123)
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTInt64ValueTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"123"}}"#
    #expect(got == want)
  }

  @Test(
    "Pack and Unpack Int64Value boundaries in Any",
    arguments: [
      Int64.min,
      Int64.max,
      0,
    ])
  func int64ValueBoundaries(_ value: Int64) throws {
    let any = try WKTAny(fromMessage: value)
    let wrapped = WKTInt64ValueTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let gotJson = String(data: data, encoding: .utf8)!
    let wantJson =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"\#(value)"}}"#
    #expect(gotJson == wantJson)

    let decoder = _ProtoJSONDecoder()
    let decodedWrapped = try decoder.decode(WKTInt64ValueTests.WrappedAny.self, from: data)
    let unpacked = try Int64(fromAny: decodedWrapped.content)
    #expect(unpacked == value)
  }

  @Test(
    "Unpack Int64Value invalid value field in Any",
    arguments: [
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"not-a-number"}}"#,
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"9223372036854775808"}}"#,
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":123.45}}"#,
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":true}}"#,
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":{}}}"#,
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":[]}}"#,
    ])
  func int64ValueInvalidValue(_ json: String) throws {
    let data = Data(json.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTInt64ValueTests.WrappedAny.self, from: data)
    #expect(throws: WKTAnyError.invalidValueField) {
      let _ = try Int64(fromAny: wrapped.content)
    }
  }
}
