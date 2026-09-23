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

@Suite struct WKTStringValueTests {
  struct WrappedStringValueEncode: Encodable {
    let value: GoogleWKT.WKTStringValue?
  }

  @Test(
    "StringValue JSON Encoding",
    arguments: [
      ("hello", "{\"value\":\"hello\"}"),
      ("", "{\"value\":\"\"}"),
    ])
  func encodeJSON(_ args: (String, String)) throws {
    let wrapped = WrappedStringValueEncode(value: args.0)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("StringValue JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedStringValueEncode(value: nil)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedStringValueDecode: Decodable {
    let value: GoogleWKT.WKTStringValue?
  }

  @Test(
    "StringValue JSON Decoding",
    arguments: [
      ("{\"value\":\"hello\"}", "hello"),
      ("{\"value\":\"\"}", ""),
    ])
  func decodeJSON(_ args: (String, String)) throws {
    let data = Data(args.0.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedStringValueDecode.self, from: data)
    #expect(wrapped.value == args.1)
  }

  @Test("StringValue JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedStringValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleWKT.WKTAny
  }

  @Test("Unpack StringValue from Any")
  func stringValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTStringValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.StringValue")

    let got = try WKTStringValue(fromAny: any)
    let want = "hello"
    #expect(got == want)
  }

  @Test func stringValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"hello"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTStringValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) { let _ = try WKTStringValue(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack StringValue into Any")
  func stringValueAnyPack() throws {
    let input = WKTStringValue("hello")
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTStringValueTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}}"#
    #expect(got == want)
  }
}
