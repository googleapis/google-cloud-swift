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

@Suite struct ProtoJSONDecoderTest {
  @Test func decodeMissingMapNested() throws {
    let input = """
      {
        "repeatedMessage":[ {}, {} ]
      }
      """
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithRepeated.self, from: Data(input.utf8))
    let want = MessageWithRepeated(
      repeatedMessage: [
        MapPrimitives(),
        MapPrimitives(),
      ])
    #expect(got == want)
  }

  struct MessageWithRepeated: Codable, Equatable, _AnyPackable, Sendable {
    static var _anyTypeUrl: String { "type.googleapis.com/test.MessageWithRepeated" }

    var repeatedMessage: [MapPrimitives] = []
    var repeatedString: [String] = []
    var repeatedData: [Data] = []
    var repeatedNested: [RequiredPrimitives] = []

    init(
      repeatedMessage: [MapPrimitives] = [],
      repeatedString: [String] = [],
      repeatedData: [Data] = [],
      repeatedNested: [RequiredPrimitives] = []
    ) {
      self.repeatedMessage = repeatedMessage
      self.repeatedString = repeatedString
      self.repeatedData = repeatedData
      self.repeatedNested = repeatedNested
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }
}
