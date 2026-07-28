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
import GoogleCloudWkt
import Testing

@Suite struct BoolValueTests {
  struct WrappedBoolValueEncode: Encodable {
    let value: GoogleCloudWkt.BoolValue?
  }

  @Test(
    "BoolValue JSON Encoding",
    arguments: [
      (true, "{\"value\":true}"),
      (false, "{\"value\":false}"),
    ])
  func encodeJSON(_ args: (Bool, String)) throws {
    let wrapped = WrappedBoolValueEncode(value: args.0)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("BoolValue JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedBoolValueEncode(value: nil)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedBoolValueDecode: Decodable {
    let value: GoogleCloudWkt.BoolValue?
  }

  @Test(
    "BoolValue JSON Decoding",
    arguments: [
      ("{\"value\":true}", true),
      ("{\"value\":false}", false),
    ])
  func decodeJSON(_ args: (String, Bool)) throws {
    let data = Data(args.0.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedBoolValueDecode.self, from: data)
    #expect(wrapped.value == args.1)
  }

  @Test("BoolValue JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedBoolValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleCloudWkt.`Any`
  }

  @Test("Unpack BoolValue from Any")
  func boolValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BoolValue","value":true}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(BoolValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.BoolValue")

    let got = try BoolValue(fromAny: any)
    let want = true
    #expect(got == want)
  }

  @Test func boolValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":true}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(BoolValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) { let _ = try BoolValue(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack BoolValue into Any")
  func boolValueAnyPack() throws {
    let input = BoolValue(true)
    let any = try `Any`(fromMessage: input)
    let wrapped = BoolValueTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.BoolValue","value":true}}"#
    #expect(got == want)
  }
}
