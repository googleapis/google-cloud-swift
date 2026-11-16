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

@Suite struct FieldsFieldMask {
  typealias T = MessageWithFieldMask
  static func mask(_ paths: [String]) -> GoogleWKT.WKTFieldMask {
    GoogleWKT.WKTFieldMask(paths: paths)
  }

  @Test(
    "FieldMask fields deserialize",
    arguments: [
      (#"{}"#, T()),
      (
        #"{"singular":"userDisplayName,photo"}"#,
        T().with { $0.singular = mask(["user_display_name", "photo"]) }
      ),
      (
        #"{"optional":"userDisplayName,photo"}"#,
        T().with { $0.optional = mask(["user_display_name", "photo"]) }
      ),
      (#"{}"#, T()),
      (
        #"{"repeated":["userDisplayName,photo"]}"#,
        T().with { $0.repeated = [mask(["user_display_name", "photo"])] }
      ),
      (
        #"{"map":{"a":"userDisplayName,photo"}}"#,
        T().with { $0.map = ["a": mask(["user_display_name", "photo"])] }
      ),
      (#"{"singular":null}"#, T()),
      (#"{"optional":null}"#, T()),
      (#"{"repeated":null}"#, T()),
      (#"{"map":null}"#, T()),
    ])
  func deserialize(input: String, want: T) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(T.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test(
    "FieldMask invalid null elements throw",
    arguments: [
      #"{"repeated":[null]}"#,
      #"{"map":{"a":null}}"#,
    ])
  func invalidNullElements(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(T.self, from: Data(input.utf8))
    }
  }

  @Test(
    "FieldMask fields serialize",
    arguments: [
      (#"{}"#, T()),
      (
        #"{"singular":"userDisplayName,photo"}"#,
        T().with { $0.singular = mask(["user_display_name", "photo"]) }
      ),
      (
        #"{"optional":"userDisplayName,photo"}"#,
        T().with { $0.optional = mask(["user_display_name", "photo"]) }
      ),
      (
        #"{"repeated":["userDisplayName,photo"]}"#,
        T().with { $0.repeated = [mask(["user_display_name", "photo"])] }
      ),
      (
        #"{"map":{"a":"userDisplayName,photo"}}"#,
        T().with { $0.map = ["a": mask(["user_display_name", "photo"])] }
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
    #expect(input == roundtrip)
  }
}
