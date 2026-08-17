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

@Suite struct BoolFields {
  typealias T = MessageWithBool

  @Test(
    "bool fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular"   : false             }"#, T()),
      (#"{"singular"   : true              }"#, T().with { $0.singular = true }),
      (#"{"option"     : null              }"#, T()),
      (#"{"option"     : false             }"#, T().with { $0.option = false }),
      (#"{"option"     : true              }"#, T().with { $0.option = true }),
      (#"{"repeated"   : []                }"#, T()),
      (#"{"repeated"   : [false]           }"#, T().with { $0.repeated = [false] }),
      (#"{"repeated"   : [true, false]     }"#, T().with { $0.repeated = [true, false] }),
      (#"{"mapKey"     : {}                }"#, T()),
      (#"{"mapKey"     : {"true": "a"}     }"#, T().with { $0.mapKey = [true: "a"] }),
      (#"{"mapKeyValue": {"true": false}   }"#, T().with { $0.mapKeyValue = [true: false] }),
      (#"{"mapKeyValue": {"false": "true"} }"#, T().with { $0.mapKeyValue = [false: true] }),
      (#"{"mapValue"   : {}                }"#, T()),
      (#"{"mapValue"   : {"a": true}       }"#, T().with { $0.mapValue = ["a": true] }),
      (#"{"mapValue"   : {"a": "true"}     }"#, T().with { $0.mapValue = ["a": true] }),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    arguments: [
      (
        #"{"mapKey":{},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":false}"#,
        T()
      ),
      (
        #"{"mapKey":{"false":"a"},"mapKeyValue":{},"mapValue":{},"option":null,"repeated":[],"singular":false}"#,
        T().with { $0.mapKey = [false: "a"] }
      ),
      (
        #"{"mapKey":{},"mapKeyValue":{"false":true},"mapValue":{},"option":null,"repeated":[],"singular":false}"#,
        T().with { $0.mapKeyValue = [false: true] }
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
