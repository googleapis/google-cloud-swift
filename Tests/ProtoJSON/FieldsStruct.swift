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
@_spi(GoogleCloudInternal) import GoogleCloudWKT

@Suite struct FieldsStruct {
  typealias T = MessageWithStruct

  @Test(
    "Struct fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": null            }"#, T()),
      (#"{"singular": {}              }"#, T().with { $0.singular = [:] }),
      (#"{"singular": {"a": 42}       }"#, T().with { $0.singular = ["a": .number(42)] }),
      (#"{"singular": {"a": "hello"}  }"#, T().with { $0.singular = ["a": .string("hello")] }),
      (#"{"optional": {"a": 42}       }"#, T().with { $0.optional = ["a": .number(42)] }),
      (#"{"repeated": []              }"#, T()),
      (#"{"repeated": [{}]            }"#, T().with { $0.repeated = [[:]] }),
      (#"{"repeated": [{"a": 42}]     }"#, T().with { $0.repeated = [["a": .number(42)]] }),
      (#"{"map":      {}              }"#, T()),
      (#"{"map":      {"a": {"b": 42}}}"#, T().with { $0.map = ["a": ["b": .number(42)]] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "Struct fields serialize",
    arguments: [
      (#"{"map":{},"repeated":[]}"#, T()),
      (
        #"{"map":{},"repeated":[],"singular":{}}"#,
        T().with { $0.singular = [:] }
      ),
      (
        #"{"map":{},"repeated":[],"singular":{"a":42}}"#,
        T().with { $0.singular = ["a": .number(42)] }
      ),
      (
        #"{"map":{},"repeated":[],"singular":{"a":"hello"}}"#,
        T().with { $0.singular = ["a": .string("hello")] }
      ),
      (
        #"{"map":{},"optional":{"a":42},"repeated":[]}"#,
        T().with { $0.optional = ["a": .number(42)] }
      ),
      (
        #"{"map":{},"repeated":[{}]}"#,
        T().with { $0.repeated = [[:]] }
      ),
      (
        #"{"map":{},"repeated":[{"a":42}]}"#,
        T().with { $0.repeated = [["a": .number(42)]] }
      ),
      (
        #"{"map":{"a":{"b":42}},"repeated":[]}"#,
        T().with { $0.map = ["a": ["b": .number(42)]] }
      ),
    ]
  )
  func serialize(want: String, input: T) throws {
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
