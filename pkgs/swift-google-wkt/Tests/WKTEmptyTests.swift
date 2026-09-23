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

@Suite struct WKTEmptyTests {
  struct WrappedEmptyEncode: Encodable {
    let value: GoogleWKT.WKTEmpty
  }

  @Test("Empty JSON Encoding")
  func encodingJSON() throws {
    let wrapped = WrappedEmptyEncode(value: GoogleWKT.WKTEmpty())
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let jsonString = String(data: data, encoding: .utf8)
    #expect(jsonString == "{\"value\":{}}")
  }

  struct WrappedEmptyDecode: Decodable {
    let value: GoogleWKT.WKTEmpty
  }

  @Test("Empty JSON Decoding")
  func decodingJSON() throws {
    let jsonString = "{\"value\":{}}"
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedEmptyDecode.self, from: data)
    #expect(wrapped.value == WKTEmpty())
  }

  @Test("Unpack Empty from Any")
  func emptyAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty","value":{}}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Empty")

    let got = try WKTEmpty(fromAny: any)
    #expect(got == WKTEmpty())
  }

  @Test("Unpack Empty from empty Any (no value field)")
  func emptyAnyUnpackNoValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Empty")

    let got = try WKTEmpty(fromAny: any)
    #expect(got == WKTEmpty())
  }

  @Test func emptyAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":{}}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTEmpty(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Empty into Any")
  func emptyAnyPack() throws {
    let input = WKTEmpty()
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty"}}"#
    #expect(got == want)
  }

  @Test("Roundtrip Empty through Any directly")
  func emptyAnyDirectRoundtrip() throws {
    let input = WKTEmpty()
    let any = try WKTAny(fromMessage: input)
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Empty")
    let got = try WKTEmpty(fromAny: any)
    #expect(got == input)
  }

  @Test("Unpack Empty from Any with invalid non-empty value")
  func emptyAnyUnpackInvalidNonEmptyValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty","value":{"unexpected":"data"}}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTEmpty(fromAny: any)
    }
    #expect(error == .invalidValueField)
  }

  @Test("Unpack Empty from Any with invalid non-object value")
  func emptyAnyUnpackInvalidNonObjectValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty","value":"not-an-object"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTEmpty(fromAny: any)
    }
    #expect(error == .invalidValueField)
  }
}
