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

@Suite struct FieldMaskTests {
  struct WrappedFieldMask: Encodable {
    let value: GoogleCloudWKT.FieldMask
  }

  @Test(
    "FieldMask JSON encoding",
    arguments: [
      ([], "{\"value\":\"\"}"),
      (["user_id"], "{\"value\":\"userId\"}"),
      (["user_id", "foo_bar"], "{\"value\":\"userId,fooBar\"}"),
      (["author.profile.avatar"], "{\"value\":\"author.profile.avatar\"}"),
      (["author_profile.avatar_url"], "{\"value\":\"authorProfile.avatarUrl\"}"),
    ])
  func encodeJSON(_ paths: [String], _ expected: String) throws {
    let fieldMask = GoogleCloudWKT.FieldMask(paths: paths)
    let wrapped = WrappedFieldMask(value: fieldMask)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == expected)
  }

  struct WrappedFieldMaskDecode: Decodable {
    let value: GoogleCloudWKT.FieldMask
  }

  @Test(
    "FieldMask JSON decoding",
    arguments: [
      ("{\"value\":\"\"}", []),
      ("{\"value\":\"userId\"}", ["user_id"]),
      ("{\"value\":\"userId,fooBar\"}", ["user_id", "foo_bar"]),
      ("{\"value\":\"author.profile.avatar\"}", ["author.profile.avatar"]),
      ("{\"value\":\"authorProfile.avatarUrl\"}", ["author_profile.avatar_url"]),
    ])
  func decodeJSON(_ json: String, _ expected: [String]) throws {
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedFieldMaskDecode.self, from: data)
    #expect(wrapped.value.paths == expected)
  }

  @Test("Unpack FieldMask from Any")
  func fieldMaskAnyUnpack() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":"a,b,cD"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.FieldMask")

    let got = try FieldMask(fromAny: any)
    let want = FieldMask(paths: ["a", "b", "c_d"])
    #expect(got == want)
  }

  @Test func fieldMaskAnyUnpackMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":"a,b,cD"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try FieldMask(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test("Pack FieldMask into Any")
  func fieldMaskAnyPack() throws {
    let input = FieldMask(paths: ["a", "b", "c_d"])
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":"a,b,cD"}}"#
    #expect(got == want)
  }
}
