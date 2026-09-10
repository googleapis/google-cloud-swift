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
import GoogleCloudWKT
import Testing

@Suite struct BytesValueTests {
  struct WrappedBytesValueEncode: Encodable {
    let value: GoogleCloudWKT.BytesValue?
  }

  @Test(
    "BytesValue JSON Encoding",
    arguments: [
      ("hello", "{\"value\":\"aGVsbG8=\"}"),
      ("", "{\"value\":\"\"}"),
    ])
  func encodeJSON(_ args: (String, String)) throws {
    let wrapped = WrappedBytesValueEncode(value: Data(args.0.utf8))
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("BytesValue JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedBytesValueEncode(value: nil)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedBytesValueDecode: Decodable {
    let value: GoogleCloudWKT.BytesValue?
  }

  @Test(
    "BytesValue JSON Decoding",
    arguments: [
      ("{\"value\":\"aGVsbG8=\"}", "hello"),
      ("{\"value\":\"\"}", ""),
    ])
  func decodeJSON(_ args: (String, String)) throws {
    let data = Data(args.0.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedBytesValueDecode.self, from: data)
    #expect(wrapped.value == Data(args.1.utf8))
  }

  @Test("BytesValue JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedBytesValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleCloudWKT.`Any`
  }

  @Test("Unpack BytesValue from Any")
  func bytesValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGVsbG8="}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(BytesValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.BytesValue")

    let got = try BytesValue(fromAny: any)
    let want = Data("hello".utf8)
    #expect(got == want)
  }

  @Test func bytesValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"aGVsbG8="}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(BytesValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) { let _ = try BytesValue(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack BytesValue into Any")
  func bytesValueAnyPack() throws {
    let input = BytesValue(Data("hello".utf8))
    let any = try `Any`(fromMessage: input)
    let wrapped = BytesValueTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGVsbG8="}}"#
    #expect(got == want)
  }
}
