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
@_spi(GoogleCloudInternal) import GoogleWKT

extension ProtoJSONDecoderTest {
  // Only test the types that appear in sidekick messages
  // `Int` and `UInt` may be used with enums.
  struct RequiredPrimitives: Codable, Equatable, _AnyPackable, Sendable {
    static var _anyTypeUrl: String { "type.googleapis.com/test.RequiredPrimitives" }

    var fieldBool: Bool = Bool()
    var fieldInt: Int = Int()
    var fieldInt32: Int32 = Int32()
    var fieldInt64: Int64 = Int64()
    var fieldUInt: UInt = UInt()
    var fieldUInt32: UInt32 = UInt32()
    var fieldUInt64: UInt64 = UInt64()
    var fieldFloat: Float = Float()
    var fieldDouble: Double = Double()
    var fieldString: String = String()
    var fieldData: Data = Data()

    func with(_ config: (inout Self) -> Void) -> Self {
      var copy = self
      config(&copy)
      return copy
    }

    init() {}

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  static let requiredInputs: [(String, RequiredPrimitives)] = [
    (#"{}"#, RequiredPrimitives()),
    (#"{"fieldBool":   true }"#, RequiredPrimitives().with { $0.fieldBool = true }),
    (#"{"fieldInt":    42   }"#, RequiredPrimitives().with { $0.fieldInt = 42 }),
    (#"{"fieldInt32":  42   }"#, RequiredPrimitives().with { $0.fieldInt32 = 42 }),
    (#"{"fieldInt64":  42   }"#, RequiredPrimitives().with { $0.fieldInt64 = 42 }),
    (#"{"fieldUInt":   42   }"#, RequiredPrimitives().with { $0.fieldUInt = 42 }),
    (#"{"fieldUInt32": 42   }"#, RequiredPrimitives().with { $0.fieldUInt32 = 42 }),
    (#"{"fieldUInt64": 42   }"#, RequiredPrimitives().with { $0.fieldUInt64 = 42 }),
    (#"{"fieldFloat":  42   }"#, RequiredPrimitives().with { $0.fieldFloat = 42 }),
    (#"{"fieldDouble": 42   }"#, RequiredPrimitives().with { $0.fieldDouble = 42 }),
    (#"{"fieldString": "42" }"#, RequiredPrimitives().with { $0.fieldString = "42" }),
    (
      #"{"fieldData":   "NDI=" }"#,
      RequiredPrimitives().with {
        $0.fieldData = Data(base64Encoded: "NDI=")!
      }
    ),
    (
      #"{"fieldData":   "NDI" }"#,
      RequiredPrimitives().with {
        $0.fieldData = Data("42".utf8)
      }
    ),
    (
      #"{"fieldData":   "-_-_" }"#,
      RequiredPrimitives().with {
        $0.fieldData = Data([251, 255, 191] as [UInt8])
      }
    ),
    (
      #"{"fieldData":   "Pz8_Pw" }"#,
      RequiredPrimitives().with {
        $0.fieldData = Data("????".utf8)
      }
    ),
    (
      #"{"fieldData":   "Pz8_Pw==" }"#,
      RequiredPrimitives().with {
        $0.fieldData = Data("????".utf8)
      }
    ),
    (#"{"fieldBool":   "true" }"#, RequiredPrimitives().with { $0.fieldBool = true }),
    (#"{"fieldInt":    "42"   }"#, RequiredPrimitives().with { $0.fieldInt = 42 }),
    (#"{"fieldInt32":  "42"   }"#, RequiredPrimitives().with { $0.fieldInt32 = 42 }),
    (#"{"fieldInt64":  "42"   }"#, RequiredPrimitives().with { $0.fieldInt64 = 42 }),
    (#"{"fieldUInt":   "42"   }"#, RequiredPrimitives().with { $0.fieldUInt = 42 }),
    (#"{"fieldUInt32": "42"   }"#, RequiredPrimitives().with { $0.fieldUInt32 = 42 }),
    (#"{"fieldUInt64": "42"   }"#, RequiredPrimitives().with { $0.fieldUInt64 = 42 }),
    (#"{"fieldFloat":  "42"   }"#, RequiredPrimitives().with { $0.fieldFloat = 42 }),
    (#"{"fieldDouble": "42"   }"#, RequiredPrimitives().with { $0.fieldDouble = 42 }),
  ]

  static let requiredBadInputs: [String] = [
    #"{"fieldBool":   "bad" }"#,
    #"{"fieldInt":    "bad" }"#,
    #"{"fieldInt32":  "bad" }"#,
    #"{"fieldInt64":  "bad" }"#,
    #"{"fieldUInt":   "bad" }"#,
    #"{"fieldUInt32": "bad" }"#,
    #"{"fieldUInt64": "bad" }"#,
    #"{"fieldFloat":  "bad" }"#,
    #"{"fieldDouble": "bad" }"#,
    // #"{"fieldString": 42 }"#, Returns a different error
    #"{"fieldData":   "bad!" }"#,
    #"{"fieldData":   "a" }"#,
    #"{"fieldData":   "NDI==" }"#,
    #"{"fieldData":   "QUJD=" }"#,
    #"{"fieldData":   "QQ=A" }"#,
    #"{"fieldData":   "-_+/" }"#,
  ]

  @Test("decode required", arguments: requiredInputs)
  func decodeRequired(input: String, want: RequiredPrimitives) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(RequiredPrimitives.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test("decode required bad inputs", arguments: requiredBadInputs)
  func decodeRequiredBad(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(RequiredPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test func decodeRequiredBadString() throws {
    let input = #"{"fieldString": 42 }"#
    let decoder = _ProtoJSONDecoder()
    let error = #expect(throws: DecodingError.self) {
      try decoder.decode(OptionalPrimitives.self, from: Data(input.utf8))
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }
}
