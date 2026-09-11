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

@Suite struct FieldsValue {
  typealias T = MessageWithValue

  @Test(
    "Value fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": null         }"#, T()),
      (#"{"singular": 42           }"#, T().with { $0.singular = .number(42) }),
      (#"{"singular": "42"         }"#, T().with { $0.singular = .string("42") }),
      (#"{"singular": "hello"      }"#, T().with { $0.singular = .string("hello") }),
      (#"{"singular": true         }"#, T().with { $0.singular = .bool(true) }),
      (#"{"singular": {}           }"#, T().with { $0.singular = .object([:]) }),
      (#"{"singular": []           }"#, T().with { $0.singular = .array([]) }),
      (#"{"optional": 42           }"#, T().with { $0.optional = .number(42) }),
      (#"{"repeated": []           }"#, T()),
      (#"{"repeated": [null]       }"#, T().with { $0.repeated = [.null(NullValue())] }),
      (
        #"{"repeated": [42, "hello"]}"#, T().with { $0.repeated = [.number(42), .string("hello")] }
      ),
      (#"{"map":      {}           }"#, T()),
      (#"{"map":      {"a": 42}    }"#, T().with { $0.map = ["a": .number(42)] }),
      (#"{"map":      {"a": null}  }"#, T().with { $0.map = ["a": .null(NullValue())] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "Value fields serialize",
    arguments: [
      (#"{"map":{},"optional":null,"repeated":[],"singular":null}"#, T()),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":42}"#,
        T().with { $0.singular = .number(42) }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":"hello"}"#,
        T().with { $0.singular = .string("hello") }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":true}"#,
        T().with { $0.singular = .bool(true) }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":{}}"#,
        T().with { $0.singular = .object([:]) }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":[]}"#,
        T().with { $0.singular = .array([]) }
      ),
      (
        #"{"map":{},"optional":42,"repeated":[],"singular":null}"#,
        T().with { $0.optional = .number(42) }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[null],"singular":null}"#,
        T().with { $0.repeated = [.null(NullValue())] }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[42,"hello"],"singular":null}"#,
        T().with { $0.repeated = [.number(42), .string("hello")] }
      ),
      (
        #"{"map":{"a":42},"optional":null,"repeated":[],"singular":null}"#,
        T().with { $0.map = ["a": .number(42)] }
      ),
      (
        #"{"map":{"a":null},"optional":null,"repeated":[],"singular":null}"#,
        T().with { $0.map = ["a": .null(NullValue())] }
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
