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

@Suite struct FieldsEnum {
  typealias T = MessageWithEnum

  @Test(
    "Enum fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (#"{"singular": 0}"#, T().with { $0.singular = .unspecified }),
      (#"{"singular": "TEST_ENUM_UNSPECIFIED"}"#, T().with { $0.singular = .unspecified }),
      (#"{"singular": 1}"#, T().with { $0.singular = .red }),
      (#"{"singular": "RED"}"#, T().with { $0.singular = .red }),
      (#"{"singular": "CYAN"}"#, T().with { $0.singular = .unknownStringValue("CYAN") }),
      (#"{"singular": "42"}"#, T().with { $0.singular = .unknownIntValue(42) }),
      (#"{"optional": 2}"#, T().with { $0.optional = .green }),
      (#"{"optional": "GREEN"}"#, T().with { $0.optional = .green }),
      (#"{"optional": null}"#, T()),
      (#"{"optional": "CYAN"}"#, T().with { $0.optional = .unknownStringValue("CYAN") }),
      (#"{"optional": "42"}"#, T().with { $0.optional = .unknownIntValue(42) }),
      (#"{"optional": 42}"#, T().with { $0.optional = .unknownIntValue(42) }),
      (#"{"repeated": [1, 3, "BLUE"]}"#, T().with { $0.repeated = [.red, .blue, .blue] }),
      (#"{"repeated": [42]}"#, T().with { $0.repeated = [.unknownIntValue(42)] }),
      (#"{"repeated": ["CYAN"]}"#, T().with { $0.repeated = [.unknownStringValue("CYAN")] }),
      (#"{"map": {"a": 2}}"#, T().with { $0.map = ["a": .green] }),
      (#"{"map": {"a": 42}}"#, T().with { $0.map = ["a": .unknownIntValue(42)] }),
      (#"{"map": {"a": "MAGENTA"}}"#, T().with { $0.map = ["a": .unknownStringValue("MAGENTA")] }),
    ])
  func deserialize(input: String, want: MessageWithEnum) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithEnum.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "Enum fields serialize",
    arguments: [
      (#"{"map":{},"optional":null,"repeated":[],"singular":0}"#, T()),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":0}"#,
        T().with { $0.singular = .unspecified }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":1}"#,
        T().with { $0.singular = .red }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":"CYAN"}"#,
        T().with { $0.singular = .unknownStringValue("CYAN") }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[],"singular":42}"#,
        T().with { $0.singular = .unknownIntValue(42) }
      ),
      (
        #"{"map":{},"optional":2,"repeated":[],"singular":0}"#,
        T().with { $0.optional = .green }
      ),
      (
        #"{"map":{},"optional":"CYAN","repeated":[],"singular":0}"#,
        T().with { $0.optional = .unknownStringValue("CYAN") }
      ),
      (
        #"{"map":{},"optional":42,"repeated":[],"singular":0}"#,
        T().with { $0.optional = .unknownIntValue(42) }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[1,3,3],"singular":0}"#,
        T().with { $0.repeated = [.red, .blue, .blue] }
      ),
      (
        #"{"map":{},"optional":null,"repeated":[42],"singular":0}"#,
        T().with { $0.repeated = [.unknownIntValue(42)] }
      ),
      (
        #"{"map":{},"optional":null,"repeated":["CYAN"],"singular":0}"#,
        T().with { $0.repeated = [.unknownStringValue("CYAN")] }
      ),
      (
        #"{"map":{"a":2},"optional":null,"repeated":[],"singular":0}"#,
        T().with { $0.map = ["a": .green] }
      ),
      (
        #"{"map":{"a":42},"optional":null,"repeated":[],"singular":0}"#,
        T().with { $0.map = ["a": .unknownIntValue(42)] }
      ),
      (
        #"{"map":{"a":"MAGENTA"},"optional":null,"repeated":[],"singular":0}"#,
        T().with { $0.map = ["a": .unknownStringValue("MAGENTA")] }
      ),
    ])
  func serialize(want: String, input: MessageWithEnum) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(input)
    let jsonString = String(data: data, encoding: .utf8)!
    #expect(jsonString == want)
  }

  @Test("Use enum with @unknown")
  func useEnum() throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithEnum.self, from: Data("{}".utf8))
    #expect(got.singular == .unspecified)
    switch got.singular {
    case .unspecified:
      #expect(Bool(true), "\(got)")
    case .red, .green, .blue:
      #expect(Bool(false), "\(got)")
    case .unknownIntValue, .unknownStringValue:
      #expect(Bool(false), "\(got)")
    @unknown default:
      #expect(Bool(true), "\(got)")
    }
  }
}
