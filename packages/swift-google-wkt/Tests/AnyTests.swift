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

@Suite struct AnyTests {
  struct WrappedAny: Codable {
    let content: GoogleCloudWKT.`Any`
  }

  // Storing an Any into an Any is probably a bad idea, but that won't stop them.
  @Test("Decoding Any")
  func testDecodingAny() throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Any","value":{"@type":"type.googleapis.com/google.protobuf.Duration","value":"123.450s"}}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == "type.googleapis.com/google.protobuf.Any")

    let innerAny = try `Any`(fromAny: any)
    #expect(innerAny.typeUrl == "type.googleapis.com/google.protobuf.Duration")

    let got = try Duration(fromAny: innerAny)
    let want = try Duration(seconds: 123, nanos: 450_000_000)
    #expect(got == want)
  }

  @Test func testDecodingAnyMismatchedUrl() throws {
    let jsonString =
      #"{"content":{"@type":"bad","value":{"@type":"type.googleapis.com/google.protobuf.Duration","value":"123.450s"}}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.mismatchedTypeUrl) {
      let _ = try `Any`(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  // Storing an Any into an Any is probably a bad idea, but that won't stop them.
  @Test("Encoding Any")
  func testEncodingAny() throws {
    let input = try Duration(seconds: 123, nanos: 450_000_000)
    let innerAny = try `Any`(fromMessage: input)
    let any = try `Any`(fromMessage: innerAny)
    let wrapped = WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      #"{"content":{"@type":"type.googleapis.com/google.protobuf.Any","value":{"@type":"type.googleapis.com/google.protobuf.Duration","value":"123.450s"}}}"#
    #expect(got == want)
  }
}
