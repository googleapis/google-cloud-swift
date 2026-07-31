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

@Suite struct FloatValueTests {
  struct WrappedFloatValueEncode: Encodable {
    let value: GoogleCloudWkt.FloatValue?
  }

  @Test(
    "FloatValue JSON Encoding",
    arguments: [
      (123.45, "{\"value\":123.45}"),
      (0.0, "{\"value\":0}"),
    ])
  func encodeJSON(_ args: (Float, String)) throws {
    let wrapped = WrappedFloatValueEncode(value: args.0)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == args.1)
  }

  @Test("FloatValue JSON Encoding unset")
  func encodeJSONUnset() throws {
    let wrapped = WrappedFloatValueEncode(value: nil)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{}")
  }

  struct WrappedFloatValueDecode: Decodable {
    let value: GoogleCloudWkt.FloatValue?
  }

  @Test(
    "FloatValue JSON Decoding",
    arguments: [
      ("{\"value\":123.45}", 123.45),
      ("{\"value\":0}", 0.0),
    ])
  func decodeJSON(_ args: (String, Float)) throws {
    let data = Data(args.0.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedFloatValueDecode.self, from: data)
    #expect(wrapped.value == args.1)
  }

  @Test("FloatValue JSON Decoding unset")
  func decodeJSONUnset() throws {
    let data = Data("{}".utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedFloatValueDecode.self, from: data)
    #expect(wrapped.value == nil)
  }

  struct WrappedAny: Codable {
    let content: GoogleCloudWkt.`Any`
  }

  @Test("Unpack FloatValue from Any")
  func floatValueAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":123.45}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(FloatValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.FloatValue")

    let got = try FloatValue(fromAny: any)
    let want = Float(123.45)
    #expect(got == want)
  }

  @Test func floatValueAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":123.45}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(FloatValueTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) { let _ = try FloatValue(fromAny: any) }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack FloatValue into Any")
  func floatValueAnyPack() throws {
    let input = FloatValue(123.45)
    let any = try `Any`(fromMessage: input)
    let wrapped = FloatValueTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":123.45}}"#
    #expect(got == want)
  }
}
