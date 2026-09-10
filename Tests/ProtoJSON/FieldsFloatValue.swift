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

@Suite struct FieldsFloatValue {
  typealias T = MessageWithFloatValue

  @Test(
    "FloatValue fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": null         }"#, T()),
      (#"{"singular": 4.2          }"#, T().with { $0.singular = 4.2 }),
      (#"{"singular": "4.2"        }"#, T().with { $0.singular = 4.2 }),
      (#"{"repeated": []           }"#, T()),
      (#"{"repeated": [4.2]        }"#, T().with { $0.repeated = [4.2] }),
      (#"{"map":      {}           }"#, T()),
      (#"{"map":      {"a": 4.2 }  }"#, T().with { $0.map = ["a": 4.2] }),
      (#"{"singular": "Infinity"   }"#, T().with { $0.singular = .infinity }),
      (#"{"singular": "-Infinity"  }"#, T().with { $0.singular = -.infinity }),
      (
        #"{"repeated": ["Infinity", "-Infinity"]}"#,
        T().with { $0.repeated = [.infinity, -.infinity] }
      ),
      (#"{"map":      {"a": "Infinity"} }"#, T().with { $0.map = ["a": .infinity] }),
      (#"{"map":      {"a": "-Infinity"} }"#, T().with { $0.map = ["a": -.infinity] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "FloatValue fields deserialize NaN",
    arguments: [
      (
        #"{"singular": "NaN"        }"#,
        { @Sendable (got: T) -> Float32? in got.singular }
      ),
      (
        #"{"repeated": ["NaN"]      }"#,
        { @Sendable (got: T) -> Float32? in got.repeated.first }
      ),
      (
        #"{"map":      {"a": "NaN"} }"#,
        { @Sendable (got: T) -> Float32? in got.map["a"] }
      ),
    ]
  ) func deserializeNaN(input: String, value: @Sendable (T) -> Float32?) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(value(got).map({ $0.isNaN }) ?? false, "got=\(got)")
  }

  @Test(
    "FloatValue fields serialize",
    arguments: [
      (
        #"{"map":{},"repeated":[]}"#,
        T()
      ),
      (
        #"{"map":{},"repeated":[],"singular":4.2}"#,
        T().with { $0.singular = 4.2 }
      ),
      (
        #"{"map":{},"repeated":[],"singular":"Infinity"}"#,
        T().with { $0.singular = .infinity }
      ),
      (
        #"{"map":{},"repeated":[],"singular":"-Infinity"}"#,
        T().with { $0.singular = -.infinity }
      ),
      (
        #"{"map":{},"repeated":[],"singular":"NaN"}"#,
        T().with { $0.singular = .nan }
      ),
      (
        #"{"map":{},"repeated":["Infinity","-Infinity"]}"#,
        T().with { $0.repeated = [.infinity, -.infinity] }
      ),
      (
        #"{"map":{},"repeated":["NaN"]}"#,
        T().with { $0.repeated = [.nan] }
      ),
      (
        #"{"map":{"a":"Infinity"},"repeated":[]}"#,
        T().with { $0.map = ["a": .infinity] }
      ),
      (
        #"{"map":{"a":"-Infinity"},"repeated":[]}"#,
        T().with { $0.map = ["a": -.infinity] }
      ),
      (
        #"{"map":{"a":"NaN"},"repeated":[]}"#,
        T().with { $0.map = ["a": .nan] }
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
    let isNaN =
      (input.singular?.isNaN ?? false)
      || input.repeated.contains(where: { $0.isNaN })
      || input.map.values.contains(where: { $0.isNaN })
    if !isNaN {
      #expect(input == roundtrip)
    }
  }
}
