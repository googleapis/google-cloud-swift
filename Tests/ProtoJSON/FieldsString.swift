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
import Testing
@_spi(GoogleCloudInternal) import GoogleWKT

@Suite struct StringFields {
  typealias T = MessageWithString

  @Test(
    "string fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular":""}"#, T()),
      (#"{"singular":"42"}"#, T().with { $0.singular = "42" }),
      (#"{"option":null}"#, T()),
      (#"{"option":""}"#, T().with { $0.option = "" }),
      (#"{"option":"42"}"#, T().with { $0.option = "42" }),
      (#"{}"#, T()),
      (#"{"repeated":[""]}"#, T().with { $0.repeated = [""] }),
      (#"{"repeated":["4","2"]}"#, T().with { $0.repeated = ["4", "2"] }),
      (#"{}"#, T()),
      (#"{"mapValue":{"42":"a"}}"#, T().with { $0.mapValue = [42: "a"] }),
      (#"{}"#, T()),
      (#"{"mapKey":{"4":2}}"#, T().with { $0.mapKey = ["4": 2] }),
      (#"{"mapKey":{"4":"2"}}"#, T().with { $0.mapKey = ["4": 2] }),
      (#"{}"#, T()),
      (#"{"mapKeyValue":{"4":"2"}}"#, T().with { $0.mapKeyValue = ["4": "2"] }),
      (#"{"singular":null}"#, T()),
      (#"{"repeated":null}"#, T()),
      (#"{"mapValue":null}"#, T()),
      (#"{"mapKey":null}"#, T()),
      (#"{"mapKeyValue":null}"#, T()),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "string invalid null elements throw",
    arguments: [
      #"{"repeated":[null]}"#,
      #"{"mapValue":{"42":null}}"#,
      #"{"mapKey":{"4":null}}"#,
      #"{"mapKeyValue":{"4":null}}"#,
    ])
  func invalidNullElements(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(T.self, from: Data(input.utf8))
    }
  }

  @Test(
    arguments: [
      (
        #"{"singular":""}"#,
        T()
      ),
      (
        #"{"mapKey":{"a":42},"singular":""}"#,
        T().with { $0.mapKey = ["a": 42] }
      ),
      (
        #"{"mapValue":{"42":"a"},"singular":""}"#,
        T().with { $0.mapValue = [42: "a"] }
      ),
    ])
  func roundtrip(want: String, input: T) throws {
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == want)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(T.self, from: data)
    #expect(input == roundtrip)
  }
}
