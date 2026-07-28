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
  struct RepeatedPrimitives: Decodable, Equatable {
    func with(_ config: (inout Self) -> Void) -> Self {
      var copy = self
      config(&copy)
      return copy
    }
    var fieldBool: [Bool] = []
    var fieldInt: [Int] = []
    var fieldInt32: [Int32] = []
    var fieldInt64: [Int64] = []
    var fieldUInt: [UInt] = []
    var fieldUInt32: [UInt32] = []
    var fieldUInt64: [UInt64] = []
    var fieldFloat: [Float] = []
    var fieldDouble: [Double] = []
    var fieldString: [String] = []
    var fieldData: [Data] = []
  }

  @Test(
    "decode repeated primitives",
    arguments: [
      (#"{}"#, RepeatedPrimitives()),
      (#"{"fieldBool":   []       }"#, RepeatedPrimitives()),
      (#"{"fieldInt":    []       }"#, RepeatedPrimitives()),
      (#"{"fieldInt32":  []       }"#, RepeatedPrimitives()),
      (#"{"fieldInt64":  []       }"#, RepeatedPrimitives()),
      (#"{"fieldUInt":   []       }"#, RepeatedPrimitives()),
      (#"{"fieldUInt32": []       }"#, RepeatedPrimitives()),
      (#"{"fieldUInt64": []       }"#, RepeatedPrimitives()),
      (#"{"fieldFloat":  []       }"#, RepeatedPrimitives()),
      (#"{"fieldDouble": []       }"#, RepeatedPrimitives()),
      (#"{"fieldString": []       }"#, RepeatedPrimitives()),
      (#"{"fieldData":   []       }"#, RepeatedPrimitives()),
      (#"{"fieldBool":   [true]   }"#, RepeatedPrimitives().with { $0.fieldBool = [true] }),
      (#"{"fieldInt":    [42]     }"#, RepeatedPrimitives().with { $0.fieldInt = [42] }),
      (#"{"fieldInt32":  [42]     }"#, RepeatedPrimitives().with { $0.fieldInt32 = [42] }),
      (#"{"fieldInt64":  [42]     }"#, RepeatedPrimitives().with { $0.fieldInt64 = [42] }),
      (#"{"fieldUInt":   [42]     }"#, RepeatedPrimitives().with { $0.fieldUInt = [42] }),
      (#"{"fieldUInt32": [42]     }"#, RepeatedPrimitives().with { $0.fieldUInt32 = [42] }),
      (#"{"fieldUInt64": [42]     }"#, RepeatedPrimitives().with { $0.fieldUInt64 = [42] }),
      (#"{"fieldFloat":  [42]     }"#, RepeatedPrimitives().with { $0.fieldFloat = [42] }),
      (#"{"fieldDouble": [42]     }"#, RepeatedPrimitives().with { $0.fieldDouble = [42] }),
      (#"{"fieldString": [""]     }"#, RepeatedPrimitives().with { $0.fieldString = [""] }),
      (#"{"fieldData":   [""]     }"#, RepeatedPrimitives().with { $0.fieldData = [Data()] }),
      (#"{"fieldBool":   ["true"] }"#, RepeatedPrimitives().with { $0.fieldBool = [true] }),
      (#"{"fieldInt":    ["42"]   }"#, RepeatedPrimitives().with { $0.fieldInt = [42] }),
      (#"{"fieldInt32":  ["42"]   }"#, RepeatedPrimitives().with { $0.fieldInt32 = [42] }),
      (#"{"fieldInt64":  ["42"]   }"#, RepeatedPrimitives().with { $0.fieldInt64 = [42] }),
      (#"{"fieldUInt":   ["42"]   }"#, RepeatedPrimitives().with { $0.fieldUInt = [42] }),
      (#"{"fieldUInt32": ["42"]   }"#, RepeatedPrimitives().with { $0.fieldUInt32 = [42] }),
      (#"{"fieldUInt64": ["42"]   }"#, RepeatedPrimitives().with { $0.fieldUInt64 = [42] }),
      (#"{"fieldFloat":  ["42"]   }"#, RepeatedPrimitives().with { $0.fieldFloat = [42] }),
      (#"{"fieldDouble": ["42"]   }"#, RepeatedPrimitives().with { $0.fieldDouble = [42] }),
      (#"{"fieldString": ["42"]   }"#, RepeatedPrimitives().with { $0.fieldString = ["42"] }),
      (
        #"{"fieldData":   ["NDI="] }"#,
        RepeatedPrimitives().with { $0.fieldData = [Data(base64Encoded: "NDI=")!] }
      ),
    ])
  func decodeRepeated(input: String, want: RepeatedPrimitives) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(RepeatedPrimitives.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "decode repeated bad inputs",
    arguments: [
      #"{"fieldBool":   ["bad"] }"#,
      #"{"fieldInt":    ["bad"] }"#,
      #"{"fieldInt32":  ["bad"] }"#,
      #"{"fieldInt64":  ["bad"] }"#,
      #"{"fieldUInt":   ["bad"] }"#,
      #"{"fieldUInt32": ["bad"] }"#,
      #"{"fieldUInt64": ["bad"] }"#,
      #"{"fieldFloat":  ["bad"] }"#,
      #"{"fieldDouble": ["bad"] }"#,
      #"{"fieldData":   ["bad"] }"#,
    ])
  func decodeRepeatedBad(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(RepeatedPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test func decodeRepeatedBadString() throws {
    let input = #"{"fieldData":   [42] }"#
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(RepeatedPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }
}
