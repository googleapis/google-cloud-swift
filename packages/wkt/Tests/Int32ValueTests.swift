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

@Suite struct Int32ValueTests {
  struct WrappedInt32ValueEncode: Encodable {
    let value: GoogleCloudWKT.Int32Value?
  }

  @Test(
    "Int32Value JSON Encoding",
    arguments: [
      (123, "{\"value\":123}"),
      (0, "{\"value\":0}"),
    ])
  func encodeJSON(_ args: (Int32, String)) throws {
    let wrapped = WrappedInt32ValueEncode(value: args.0)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("Int32Value JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedInt32ValueEncode(value: nil)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedInt32ValueDecode: Decodable {
    let value: GoogleCloudWKT.Int32Value?
  }

  @Test(
    "Int32Value JSON Decoding",
    arguments: [
      ("{\"value\":123}", 123),
      ("{\"value\":0}", 0),
    ])
  func decodeJSON(_ args: (String, Int32)) throws {
    let data = Data(args.0.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedInt32ValueDecode.self, from: data)
    #expect(wrapped.value == args.1)
  }

  @Test("Int32Value JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedInt32ValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleCloudWKT.`Any`
  }

  @Test("Unpack Int32Value from Any")
  func int32ValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":123}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(Int32ValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Int32Value")

    let got = try Int32Value(fromAny: any)
    let want = Int32(123)
    #expect(got == want)
  }

  @Test func int32ValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":123}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(Int32ValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) { let _ = try Int32Value(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Int32Value into Any")
  func int32ValueAnyPack() throws {
    let input = Int32Value(123)
    let any = try `Any`(fromMessage: input)
    let wrapped = Int32ValueTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":123}}"#
    #expect(got == want)
  }
}
