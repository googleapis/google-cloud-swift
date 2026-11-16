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

@Suite struct Int32Fields {
  typealias T = MessageWithI32

  @Test(
    "int32 fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular":0}"#, T()),
      (#"{"singular":42}"#, T().with { $0.singular = 42 }),
      (#"{"singular":"42"}"#, T().with { $0.singular = 42 }),
      (#"{"option":null}"#, T()),
      (#"{"option":0}"#, T().with { $0.option = 0 }),
      (#"{"option":42}"#, T().with { $0.option = 42 }),
      (#"{"option":"42"}"#, T().with { $0.option = 42 }),
      (#"{}"#, T()),
      (#"{"repeated":[0]}"#, T().with { $0.repeated = [0] }),
      (#"{"repeated":[4,2]}"#, T().with { $0.repeated = [4, 2] }),
      (#"{"repeated":["4","2"]}"#, T().with { $0.repeated = [4, 2] }),
      (#"{}"#, T()),
      (#"{"mapKey":{"42":"a"}}"#, T().with { $0.mapKey = [42: "a"] }),
      (#"{"mapKeyValue":{"42":7}}"#, T().with { $0.mapKeyValue = [42: 7] }),
      (#"{"mapKeyValue":{"7":"42"}}"#, T().with { $0.mapKeyValue = [7: 42] }),
      (#"{}"#, T()),
      (#"{"mapValue":{"a":42}}"#, T().with { $0.mapValue = ["a": 42] }),
      (#"{"mapValue":{"a":"42"}}"#, T().with { $0.mapValue = ["a": 42] }),
      (#"{"singular":null}"#, T()),
      (#"{"repeated":null}"#, T()),
      (#"{"mapKey":null}"#, T()),
      (#"{"mapKeyValue":null}"#, T()),
      (#"{"mapValue":null}"#, T()),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "int32 invalid null elements throw",
    arguments: [
      #"{"repeated":[null]}"#,
      #"{"mapKey":{"42":null}}"#,
      #"{"mapKeyValue":{"42":null}}"#,
      #"{"mapValue":{"a":null}}"#,
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
        #"{"singular":0}"#,
        T()
      ),
      (
        #"{"mapKey":{"42":"a"},"singular":0}"#,
        T().with { $0.mapKey = [42: "a"] }
      ),
      (
        #"{"mapKeyValue":{"42":7},"singular":0}"#,
        T().with { $0.mapKeyValue = [42: 7] }
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
