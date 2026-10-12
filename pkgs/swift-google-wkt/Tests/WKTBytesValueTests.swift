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

@Suite struct WKTBytesValueTests {
  struct WrappedBytesValueEncode: Encodable {
    let value: GoogleWKT.WKTBytesValue?
  }

  @Test(
    "BytesValue JSON Encoding",
    arguments: [
      ("hello", "{\"value\":\"aGVsbG8=\"}"),
      ("", "{\"value\":\"\"}"),
    ])
  func encodeJSON(_ args: (String, String)) throws {
    let wrapped = WrappedBytesValueEncode(value: Data(args.0.utf8))
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("BytesValue JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedBytesValueEncode(value: nil)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedBytesValueDecode: Decodable {
    let value: GoogleWKT.WKTBytesValue?
  }

  @Test(
    "BytesValue JSON Decoding",
    arguments: [
      ("{\"value\":\"aGVsbG8=\"}", "hello"),
      ("{\"value\":\"\"}", ""),
    ])
  func decodeJSON(_ args: (String, String)) throws {
    let data = Data(args.0.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedBytesValueDecode.self, from: data)
    #expect(wrapped.value == Data(args.1.utf8))
  }

  @Test("BytesValue JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedBytesValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleWKT.WKTAny
  }

  @Test("Unpack BytesValue from Any")
  func bytesValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGVsbG8="}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTBytesValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeURL == "type.googleapis.com/google.protobuf.BytesValue")

    let got = try WKTBytesValue(fromAny: any)
    let want = Data("hello".utf8)
    #expect(got == want)
  }

  @Test func bytesValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"aGVsbG8="}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTBytesValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) { let _ = try WKTBytesValue(fromAny: any) }
    #expect(error == .mismatchedTypeURL)
  }

  @Test("Pack BytesValue into Any")
  func bytesValueAnyPack() throws {
    let input = WKTBytesValue(Data("hello".utf8))
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTBytesValueTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGVsbG8="}}"#
    #expect(got == want)
  }

  @Test(
    "Top-level BytesValue JSON Round-Trip",
    arguments: [
      ("hello", #""aGVsbG8=""#),
      ("", #""""#),
    ])
  func topLevelRoundTrip(_ args: (String, String)) throws {
    let value: WKTBytesValue = Data(args.0.utf8)
    let encoder = _ProtoJSONEncoder()
    let encoded = try encoder.encode(value)
    let gotJSON = try #require(String(data: encoded, encoding: .utf8))
    #expect(gotJSON == args.1)

    let decoder = _ProtoJSONDecoder()
    let decoded = try decoder.decode(WKTBytesValue.self, from: encoded)
    #expect(decoded == value)
  }

  @Test("Top-level Optional BytesValue JSON Round-Trip")
  func topLevelOptionalRoundTrip() throws {
    let encoder = _ProtoJSONEncoder()
    let decoder = _ProtoJSONDecoder()

    let someValue: WKTBytesValue? = Data("hello".utf8)
    let encodedSome = try encoder.encode(someValue)
    #expect(String(data: encodedSome, encoding: .utf8) == #""aGVsbG8=""#)
    let decodedSome = try decoder.decode(WKTBytesValue?.self, from: encodedSome)
    #expect(decodedSome == someValue)

    let nilValue: WKTBytesValue? = nil
    let encodedNil = try encoder.encode(nilValue)
    #expect(String(data: encodedNil, encoding: .utf8) == "null")
    let decodedNil = try decoder.decode(WKTBytesValue?.self, from: encodedNil)
    #expect(decodedNil == nil)
  }

  struct SingleValueBytesWrapper: Codable, Equatable {
    let value: WKTBytesValue

    init(_ value: WKTBytesValue) {
      self.value = value
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.value = try container.decode(WKTBytesValue.self)
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(self.value)
    }
  }

  @Test("SingleValueContainer BytesValue JSON Round-Trip")
  func singleValueContainerRoundTrip() throws {
    let wrapper = SingleValueBytesWrapper(Data("hello".utf8))
    let encoder = _ProtoJSONEncoder()
    let encoded = try encoder.encode(wrapper)
    #expect(String(data: encoded, encoding: .utf8) == #""aGVsbG8=""#)

    let decoder = _ProtoJSONDecoder()
    let decoded = try decoder.decode(SingleValueBytesWrapper.self, from: encoded)
    #expect(decoded == wrapper)
  }

  @Test("Collections of Optional BytesValue JSON Encoding")
  func optionalBytesInCollections() throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let list: [WKTBytesValue?] = [Data("hello".utf8), nil, Data()]
    let listData = try encoder.encode(list)
    #expect(String(data: listData, encoding: .utf8) == #"["aGVsbG8=",null,""]"#)

    let map: [String: WKTBytesValue?] = ["a": Data("hello".utf8), "b": nil]
    let mapData = try encoder.encode(map)
    #expect(String(data: mapData, encoding: .utf8) == #"{"a":"aGVsbG8=","b":null}"#)
  }
}
