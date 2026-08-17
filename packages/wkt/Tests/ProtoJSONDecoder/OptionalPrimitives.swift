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

extension ProtoJSONDecoderTest {
  // Only test the types that appear in sidekick messages
  // `Int` and `UInt` may be used with enums.
  struct OptionalPrimitives: Decodable, Equatable {
    var fieldBool: Bool? = nil
    var fieldInt: Int? = nil
    var fieldInt32: Int32? = nil
    var fieldInt64: Int64? = nil
    var fieldUInt: UInt? = nil
    var fieldUInt32: UInt32? = nil
    var fieldUInt64: UInt64? = nil
    var fieldFloat: Float? = nil
    var fieldDouble: Double? = nil
    var fieldString: String? = nil
    var fieldData: Data? = nil

    func with(_ config: (inout Self) -> Void) -> Self {
      var copy = self
      config(&copy)
      return copy
    }
  }

  @Test(
    "decode optionals",
    arguments: [
      (#"{}"#, OptionalPrimitives()),
      (#"{"fieldBool":   null }"#, OptionalPrimitives()),
      (#"{"fieldInt":    null }"#, OptionalPrimitives()),
      (#"{"fieldInt32":  null }"#, OptionalPrimitives()),
      (#"{"fieldInt64":  null }"#, OptionalPrimitives()),
      (#"{"fieldUInt":   null }"#, OptionalPrimitives()),
      (#"{"fieldUInt32": null }"#, OptionalPrimitives()),
      (#"{"fieldUInt64": null }"#, OptionalPrimitives()),
      (#"{"fieldFloat":  null }"#, OptionalPrimitives()),
      (#"{"fieldDouble": null }"#, OptionalPrimitives()),
      (#"{"fieldString": null }"#, OptionalPrimitives()),
      (#"{"fieldData":   null }"#, OptionalPrimitives()),
      (#"{"fieldBool":   true }"#, OptionalPrimitives().with { $0.fieldBool = true }),
      (#"{"fieldInt":    42   }"#, OptionalPrimitives().with { $0.fieldInt = 42 }),
      (#"{"fieldInt32":  42   }"#, OptionalPrimitives().with { $0.fieldInt32 = 42 }),
      (#"{"fieldInt64":  42   }"#, OptionalPrimitives().with { $0.fieldInt64 = 42 }),
      (#"{"fieldUInt":   42   }"#, OptionalPrimitives().with { $0.fieldUInt = 42 }),
      (#"{"fieldUInt32": 42   }"#, OptionalPrimitives().with { $0.fieldUInt32 = 42 }),
      (#"{"fieldUInt64": 42   }"#, OptionalPrimitives().with { $0.fieldUInt64 = 42 }),
      (#"{"fieldFloat":  42   }"#, OptionalPrimitives().with { $0.fieldFloat = 42 }),
      (#"{"fieldDouble": 42   }"#, OptionalPrimitives().with { $0.fieldDouble = 42 }),
      (#"{"fieldString": "42" }"#, OptionalPrimitives().with { $0.fieldString = "42" }),
      (
        #"{"fieldData":   "NDI=" }"#,
        OptionalPrimitives().with {
          $0.fieldData = Data(base64Encoded: "NDI=")!
        }
      ),
      (#"{"fieldBool":   "true" }"#, OptionalPrimitives().with { $0.fieldBool = true }),
      (#"{"fieldInt":    "42"   }"#, OptionalPrimitives().with { $0.fieldInt = 42 }),
      (#"{"fieldInt32":  "42"   }"#, OptionalPrimitives().with { $0.fieldInt32 = 42 }),
      (#"{"fieldInt64":  "42"   }"#, OptionalPrimitives().with { $0.fieldInt64 = 42 }),
      (#"{"fieldUInt":   "42"   }"#, OptionalPrimitives().with { $0.fieldUInt = 42 }),
      (#"{"fieldUInt32": "42"   }"#, OptionalPrimitives().with { $0.fieldUInt32 = 42 }),
      (#"{"fieldUInt64": "42"   }"#, OptionalPrimitives().with { $0.fieldUInt64 = 42 }),
      (#"{"fieldFloat":  "42"   }"#, OptionalPrimitives().with { $0.fieldFloat = 42 }),
      (#"{"fieldDouble": "42"   }"#, OptionalPrimitives().with { $0.fieldDouble = 42 }),
    ])
  func decodeOptionals(input: String, want: OptionalPrimitives) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(OptionalPrimitives.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "decode optional bad inputs",
    arguments: [
      #"{"fieldBool":   "bad" }"#,
      #"{"fieldInt":    "bad" }"#,
      #"{"fieldInt32":  "bad" }"#,
      #"{"fieldInt64":  "bad" }"#,
      #"{"fieldUInt":   "bad" }"#,
      #"{"fieldUInt32": "bad" }"#,
      #"{"fieldUInt64": "bad" }"#,
      #"{"fieldFloat":  "bad" }"#,
      #"{"fieldDouble": "bad" }"#,
      // #"{"fieldString": 42 }"#, TReturns a different error
      #"{"fieldData":   "bad" }"#,
    ])
  func decodeOptionalBad(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(OptionalPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }(), "\(error)")
  }

  @Test func decodeOptionalBadString() throws {
    let input = #"{"fieldString": 42 }"#
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(OptionalPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }
}
