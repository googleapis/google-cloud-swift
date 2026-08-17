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
@_spi(GoogleCloudInternal) import GoogleCloudWkt

@Suite struct StringFields {
  typealias T = MessageWithString

  @Test(
    "string fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular"   : ""                }"#, T()),
      (#"{"singular"   : "42"              }"#, T().with { $0.singular = "42" }),
      (#"{"option"     : null              }"#, T()),
      (#"{"option"     : ""                }"#, T().with { $0.option = "" }),
      (#"{"option"     : "42"              }"#, T().with { $0.option = "42" }),
      (#"{"repeated"   : []                }"#, T()),
      (#"{"repeated"   : [""]              }"#, T().with { $0.repeated = [""] }),
      (#"{"repeated"   : ["4", "2"]        }"#, T().with { $0.repeated = ["4", "2"] }),
      (#"{"mapValue"   : {}                }"#, T()),
      (#"{"mapValue"   : {"42": "a"}       }"#, T().with { $0.mapValue = [42: "a"] }),
      (#"{"mapKey"     : {}                }"#, T()),
      (#"{"mapKey"     : {"4": 2}          }"#, T().with { $0.mapKey = ["4": 2] }),
      (#"{"mapKey"     : {"4": "2"}        }"#, T().with { $0.mapKey = ["4": 2] }),
      (#"{"mapKeyValue": {}                }"#, T()),
      (#"{"mapKeyValue": {"4": "2"}        }"#, T().with { $0.mapKeyValue = ["4": "2"] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    arguments: [
      (
        #"{"mapKey":{},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":""}"#,
        T()
      ),
      (
        #"{"mapKey":{"a":42},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":""}"#,
        T().with { $0.mapKey = ["a": 42] }
      ),
      (
        #"{"mapKey":{},"mapKeyValue":{},"mapValue":{"42":"a"},"option":null,"repeated":[],"singular":""}"#,
        T().with { $0.mapValue = [42: "a"] }
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
