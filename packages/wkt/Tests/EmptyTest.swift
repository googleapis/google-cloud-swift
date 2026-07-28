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

@Suite struct EmptyTests {
  struct WrappedEmptyEncode: Encodable {
    let value: GoogleCloudWkt.Empty
  }

  @Test("Empty JSON Encoding")
  func encodingJSON() throws {
    let wrapped = WrappedEmptyEncode(value: GoogleCloudWkt.Empty())
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let jsonString = String(data: data, encoding: .utf8)
    #expect(jsonString == "{\"value\":{}}")
  }

  struct WrappedEmptyDecode: Decodable {
    let value: GoogleCloudWkt.Empty
  }

  @Test("Empty JSON Decoding")
  func decodingJSON() throws {
    let jsonString = "{\"value\":{}}"
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedEmptyDecode.self, from: data)
    #expect(wrapped.value == Empty())
  }

  @Test("Unpack Empty from Any")
  func emptyAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty","value":{}}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Empty")

    let got = try Empty(fromAny: any)
    #expect(got == Empty())
  }

  @Test("Unpack Empty from empty Any (no value field)")
  func emptyAnyUnpackNoValue() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Empty")

    let got = try Empty(fromAny: any)
    #expect(got == Empty())
  }

  @Test func emptyAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":{}}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try Empty(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack Empty into Any")
  func emptyAnyPack() throws {
    let input = Empty()
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Empty","value":{}}}"#
    #expect(got == want)
  }
}
