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

  struct MessageWithEnumAndNested: Codable, Equatable, _AnyPackable, Sendable {
    static var _anyTypeUrl: String { "type.googleapis.com/test.MessageWithEnumAndNested" }

    var enumValue: WKTSyntax = WKTSyntax()
    var repeatedEnum: [WKTSyntax] = []
    var mapEnum: [String: WKTSyntax] = [:]
    var mapMessage: [String: RequiredPrimitives] = [:]

    init(
      enumValue: WKTSyntax = WKTSyntax(),
      repeatedEnum: [WKTSyntax] = [],
      mapEnum: [String: WKTSyntax] = [:],
      mapMessage: [String: RequiredPrimitives] = [:]
    ) {
      self.enumValue = enumValue
      self.repeatedEnum = repeatedEnum
      self.mapEnum = mapEnum
      self.mapMessage = mapMessage
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  static let enumAndNestedInputs: [(String, MessageWithEnumAndNested)] = [
    (#"{}"#, MessageWithEnumAndNested()),
    (#"{"enumValue":null}"#, MessageWithEnumAndNested()),
    (#"{"repeatedEnum":null}"#, MessageWithEnumAndNested()),
    (#"{"mapEnum":null}"#, MessageWithEnumAndNested()),
    (#"{"mapMessage":null}"#, MessageWithEnumAndNested()),
    (
      #"{"mapMessage":{"k":{"fieldInt32":null,"fieldString":null}}}"#,
      MessageWithEnumAndNested(mapMessage: ["k": RequiredPrimitives()])
    ),
  ]

  static let enumAndNestedBadInputs: [String] = [
    #"{"repeatedEnum":[null]}"#,
    #"{"mapEnum":{"a":null}}"#,
    #"{"mapMessage":{"k":null}}"#,
  ]

  @Test("decode enum and nested null values", arguments: enumAndNestedInputs)
  func decodeEnumAndNested(input: String, want: MessageWithEnumAndNested) throws {
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(MessageWithEnumAndNested.self, from: Data(input.utf8))
    #expect(got == want)
  }

  @Test("decode enum and nested invalid null elements throw", arguments: enumAndNestedBadInputs)
  func decodeEnumAndNestedBad(input: String) throws {
    let decoder = _ProtoJSONDecoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(MessageWithEnumAndNested.self, from: Data(input.utf8))
    }
  }
}
