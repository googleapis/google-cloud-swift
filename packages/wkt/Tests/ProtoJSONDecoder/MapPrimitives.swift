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
import GoogleCloudWkt

extension ProtoJSONDecoderTest {
  // Only test the types that appear in sidekick messages
  // `Int` and `UInt` may be used with enums.
  struct MapPrimitives: Decodable, Equatable {
    func with(_ config: (inout Self) -> Void) -> Self {
      var copy = self
      config(&copy)
      return copy
    }
    var fieldBool: [String: Bool] = [:]
    var fieldInt: [String: Int] = [:]
    var fieldInt32: [String: Int32] = [:]
    var fieldInt64: [String: Int64] = [:]
    var fieldUInt: [String: UInt] = [:]
    var fieldUInt32: [String: UInt32] = [:]
    var fieldUInt64: [String: UInt64] = [:]
    var fieldFloat: [String: Float] = [:]
    var fieldDouble: [String: Double] = [:]
    var fieldString: [String: String] = [:]
    var fieldData: [String: Data] = [:]
  }

  @Test(
    "decode map primitives",
    arguments: [
      (#"{}"#, MapPrimitives()),
      (#"{"fieldBool":   {}       }"#, MapPrimitives()),
      (#"{"fieldInt":    {}       }"#, MapPrimitives()),
      (#"{"fieldInt32":  {}       }"#, MapPrimitives()),
      (#"{"fieldInt64":  {}       }"#, MapPrimitives()),
      (#"{"fieldUInt":   {}       }"#, MapPrimitives()),
      (#"{"fieldUInt32": {}       }"#, MapPrimitives()),
      (#"{"fieldUInt64": {}       }"#, MapPrimitives()),
      (#"{"fieldFloat":  {}       }"#, MapPrimitives()),
      (#"{"fieldDouble": {}       }"#, MapPrimitives()),
      (#"{"fieldString": {}       }"#, MapPrimitives()),
      (#"{"fieldData":   {}       }"#, MapPrimitives()),
      (#"{"fieldBool":   {"a": true}   }"#, MapPrimitives().with { $0.fieldBool = ["a": true] }),
      (#"{"fieldInt":    {"a": 42}     }"#, MapPrimitives().with { $0.fieldInt = ["a": 42] }),
      (#"{"fieldInt32":  {"a": 42}     }"#, MapPrimitives().with { $0.fieldInt32 = ["a": 42] }),
      (#"{"fieldInt64":  {"a": 42}     }"#, MapPrimitives().with { $0.fieldInt64 = ["a": 42] }),
      (#"{"fieldUInt":   {"a": 42}     }"#, MapPrimitives().with { $0.fieldUInt = ["a": 42] }),
      (#"{"fieldUInt32": {"a": 42}     }"#, MapPrimitives().with { $0.fieldUInt32 = ["a": 42] }),
      (#"{"fieldUInt64": {"a": 42}     }"#, MapPrimitives().with { $0.fieldUInt64 = ["a": 42] }),
      (#"{"fieldFloat":  {"a": 42}     }"#, MapPrimitives().with { $0.fieldFloat = ["a": 42] }),
      (#"{"fieldDouble": {"a": 42}     }"#, MapPrimitives().with { $0.fieldDouble = ["a": 42] }),
      (#"{"fieldString": {"a": ""}     }"#, MapPrimitives().with { $0.fieldString = ["a": ""] }),
      (#"{"fieldData":   {"a": ""}     }"#, MapPrimitives().with { $0.fieldData = ["a": Data()] }),
      (#"{"fieldBool":   {"a": "true"} }"#, MapPrimitives().with { $0.fieldBool = ["a": true] }),
      (#"{"fieldInt":    {"a": "42"}   }"#, MapPrimitives().with { $0.fieldInt = ["a": 42] }),
      (#"{"fieldInt32":  {"a": "42"}   }"#, MapPrimitives().with { $0.fieldInt32 = ["a": 42] }),
      (#"{"fieldInt64":  {"a": "42"}   }"#, MapPrimitives().with { $0.fieldInt64 = ["a": 42] }),
      (#"{"fieldUInt":   {"a": "42"}   }"#, MapPrimitives().with { $0.fieldUInt = ["a": 42] }),
      (#"{"fieldUInt32": {"a": "42"}   }"#, MapPrimitives().with { $0.fieldUInt32 = ["a": 42] }),
      (#"{"fieldUInt64": {"a": "42"}   }"#, MapPrimitives().with { $0.fieldUInt64 = ["a": 42] }),
      (#"{"fieldFloat":  {"a": "42"}   }"#, MapPrimitives().with { $0.fieldFloat = ["a": 42] }),
      (#"{"fieldDouble": {"a": "42"}   }"#, MapPrimitives().with { $0.fieldDouble = ["a": 42] }),
      (#"{"fieldString": {"a": "42"}   }"#, MapPrimitives().with { $0.fieldString = ["a": "42"] }),
      (
        #"{"fieldData":  {"a": "NDI="} }"#,
        MapPrimitives().with { $0.fieldData = ["a": Data(base64Encoded: "NDI=")!] }
      ),
    ])
  func decodeRepeated(input: String, want: MapPrimitives) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MapPrimitives.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "decode map bad inputs",
    arguments: [
      #"{"fieldBool":   {"a": "bad"} }"#,
      #"{"fieldInt":    {"a": "bad"} }"#,
      #"{"fieldInt32":  {"a": "bad"} }"#,
      #"{"fieldInt64":  {"a": "bad"} }"#,
      #"{"fieldUInt":   {"a": "bad"} }"#,
      #"{"fieldUInt32": {"a": "bad"} }"#,
      #"{"fieldUInt64": {"a": "bad"} }"#,
      #"{"fieldFloat":  {"a": "bad"} }"#,
      #"{"fieldDouble": {"a": "bad"} }"#,
      #"{"fieldData":   {"a": "bad"} }"#,
    ])
  func decodeMapBad(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(MapPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test func decodeMapBadString() throws {
    let input = #"{"fieldData":   {"a": 42} }"#
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(MapPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }
}
