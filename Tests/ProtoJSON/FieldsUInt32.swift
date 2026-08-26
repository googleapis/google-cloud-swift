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

@Suite struct UInt32Fields {
  typealias T = MessageWithU32

  @Test(
    "uint32 fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular"   : 0                 }"#, T()),
      (#"{"singular"   : 42                }"#, T().with { $0.singular = 42 }),
      (#"{"singular"   : "42"              }"#, T().with { $0.singular = 42 }),
      (#"{"option"     : null              }"#, T()),
      (#"{"option"     : 0                 }"#, T().with { $0.option = 0 }),
      (#"{"option"     : 42                }"#, T().with { $0.option = 42 }),
      (#"{"option"     : "42"              }"#, T().with { $0.option = 42 }),
      (#"{"repeated"   : []                }"#, T()),
      (#"{"repeated"   : [0]               }"#, T().with { $0.repeated = [0] }),
      (#"{"repeated"   : [4, 2]            }"#, T().with { $0.repeated = [4, 2] }),
      (#"{"repeated"   : ["4", "2"]        }"#, T().with { $0.repeated = [4, 2] }),
      (#"{"mapKey"     : {}                }"#, T()),
      (#"{"mapKey"     : {"42": "a"}       }"#, T().with { $0.mapKey = [42: "a"] }),
      (#"{"mapKeyValue": {"42": 7}         }"#, T().with { $0.mapKeyValue = [42: 7] }),
      (#"{"mapKeyValue": {"7": "42"}       }"#, T().with { $0.mapKeyValue = [7: 42] }),
      (#"{"mapValue"   : {}                }"#, T()),
      (#"{"mapValue"   : {"a": 42}         }"#, T().with { $0.mapValue = ["a": 42] }),
      (#"{"mapValue"   : {"a": "42"}       }"#, T().with { $0.mapValue = ["a": 42] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    arguments: [
      (
        #"{"mapKey":{},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":0}"#,
        T()
      ),
      (
        #"{"mapKey":{"42":"a"},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":0}"#,
        T().with { $0.mapKey = [42: "a"] }
      ),
      (
        #"{"mapKey":{},"mapKeyValue":{"42":7},"mapValue":{},"option":null,"repeated":[],"singular":0}"#,
        T().with { $0.mapKeyValue = [42: 7] }
      ),
    ])
  func roundtrip(want: String, input: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == want)

    let decoder = _ProtoJSONDecoder()
    let roundtrip = try decoder.decode(T.self, from: data)
    #expect(input == roundtrip)
  }
}
