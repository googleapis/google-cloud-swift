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

@Suite struct DoubleFields {
  typealias T = MessageWithF64

  @Test(
    "double fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": 0.0            }"#, T()),
      (#"{"singular": 1.5            }"#, T().with { $0.singular = 1.5 }),
      (#"{"singular": "1.5"          }"#, T().with { $0.singular = 1.5 }),
      (#"{"singular": "Infinity"     }"#, T().with { $0.singular = .infinity }),
      (#"{"singular": "-Infinity"    }"#, T().with { $0.singular = -.infinity }),
      (#"{"option":   null           }"#, T()),
      (#"{"option":   0.0            }"#, T().with { $0.option = 0.0 }),
      (#"{"option":   1.5            }"#, T().with { $0.option = 1.5 }),
      (#"{"option":   "1.5"          }"#, T().with { $0.option = 1.5 }),
      (#"{"repeated": []             }"#, T()),
      (#"{"repeated": [0.0]          }"#, T().with { $0.repeated = [0.0] }),
      (#"{"repeated": [1.5, -2.0]    }"#, T().with { $0.repeated = [1.5, -2.0] }),
      (#"{"repeated": ["1.5", "-2.0"]}"#, T().with { $0.repeated = [1.5, -2.0] }),
      (#"{"map":      {}             }"#, T()),
      (#"{"map":      {"a": 1.5}     }"#, T().with { $0.map = ["a": 1.5] }),
      (#"{"map":      {"a": "1.5"}   }"#, T().with { $0.map = ["a": 1.5] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  // Cannot use == with NaN, so we must some complicated predicates.
  @Test(
    "float fields deserialize NaN",
    arguments: [
      (
        #"{"singular": "NaN"        }"#,
        { @Sendable (got: T) -> Float64? in .some(got.singular) }
      ),
      (
        #"{"option":   "NaN"        }"#,
        { @Sendable (got: T) -> Float64? in got.option }
      ),
      (
        #"{"repeated": ["NaN"]      }"#,
        { @Sendable (got: T) -> Float64? in got.repeated.first }
      ),
      (
        #"{"map":      {"a": "NaN"} }"#,
        { @Sendable (got: T) -> Float64? in got.map["a"] }
      ),
    ]
  ) func deserializeNaN(input: String, value: @Sendable (T) -> Float64?) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(value(got).map({ $0.isNaN }) ?? false, "got=\(got)")
  }
}
