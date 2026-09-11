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
@_spi(GoogleCloudInternal) import GoogleCloudWKT
import SwiftProtobuf
import Testing

@Suite struct UnknownFieldsTests {
  /// A sample message struct mirroring generated message structure with `_UnknownFields`.
  struct SampleMessage: Codable, Equatable, Sendable {
    var name: String = ""
    var displayName: String = ""
    var _unknownFields = _UnknownFields()

    private enum CodingKeys: String, CodingKey {
      case name
      case displayName = "displayName"
      case _unknown

      static var _knownKeys: Set<String> {
        ["name", "displayName"]
      }
    }

    init() {}

    init(from decoder: any Swift.Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
      self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""

      let dynamicContainer = try decoder.container(keyedBy: _DynamicCodingKey.self)
      for key in dynamicContainer.allKeys where !CodingKeys._knownKeys.contains(key.stringValue) {
        self._unknownFields.json[key.stringValue] = try dynamicContainer.decode(
          Value.self,
          forKey: key
        )
      }
    }

    func encode(to encoder: any Swift.Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      if !self.name.isEmpty {
        try container.encode(self.name, forKey: .name)
      }
      if !self.displayName.isEmpty {
        try container.encode(self.displayName, forKey: .displayName)
      }

      if !self._unknownFields.json.isEmpty {
        var dynamicContainer = encoder.container(keyedBy: _DynamicCodingKey.self)
        for (key, value) in self._unknownFields.json {
          try dynamicContainer.encode(value, forKey: _DynamicCodingKey(stringValue: key))
        }
      }
    }
  }

  /// A wrapper struct to test missing nested messages with `DecodeToDefault`.
  struct WrapperMessage: Codable, Equatable, Sendable {
    var nested: SampleMessage = SampleMessage()

    private enum CodingKeys: String, CodingKey {
      case nested
    }

    init() {}

    init(from decoder: any Swift.Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.nested = try container.decode(SampleMessage.self, forKey: .nested)
    }
  }

  @Test("_UnknownFields initialization and Equatable")
  func unknownFieldsInitAndEquality() {
    let empty = _UnknownFields()
    #expect(empty.json.isEmpty)
    #expect(empty.proto.isEmpty)

    let populated = _UnknownFields(
      json: ["extra": .string("value")],
      proto: Data([0x08, 0x96, 0x01])
    )
    #expect(populated.json == ["extra": .string("value")])
    #expect(populated.proto == Data([0x08, 0x96, 0x01]))
    #expect(empty != populated)
  }

  @Test("_DynamicCodingKey initialization and Hashable")
  func dynamicCodingKeyInitAndHashable() {
    let stringKey = _DynamicCodingKey(stringValue: "customField")
    #expect(stringKey.stringValue == "customField")
    #expect(stringKey.intValue == nil)

    let intKey = _DynamicCodingKey(intValue: 42)
    #expect(intKey?.stringValue == "42")
    #expect(intKey?.intValue == 42)

    let keySet: Set<_DynamicCodingKey> = [stringKey, _DynamicCodingKey(stringValue: "customField")]
    #expect(keySet.count == 1)
  }

  @Test("JSON decoding and encoding preserves unknown fields across round-trip")
  func jsonUnknownFieldsRoundTrip() throws {
    let json = """
      {
        "name": "projects/123",
        "displayName": "Original",
        "unknownString": "hello",
        "unknownNumber": 42.5,
        "unknownBool": true,
        "unknownNull": null,
        "unknownArray": [1, "two"],
        "unknownObject": {"nestedKey": "nestedVal"}
      }
      """
    let decoder = _ProtoJSONDecoder()
    var message = try decoder.decode(SampleMessage.self, from: Data(json.utf8))

    #expect(message.name == "projects/123")
    #expect(message.displayName == "Original")
    #expect(message._unknownFields.json.count == 6)
    #expect(message._unknownFields.json["unknownString"] == .string("hello"))
    #expect(message._unknownFields.json["unknownNumber"] == .number(42.5))
    #expect(message._unknownFields.json["unknownBool"] == .bool(true))
    #expect(message._unknownFields.json["unknownNull"] == .null(NullValue()))
    #expect(
      message._unknownFields.json["unknownArray"]
        == .array([.number(1), .string("two")])
    )
    #expect(
      message._unknownFields.json["unknownObject"]
        == .object(["nestedKey": .string("nestedVal")])
    )

    // Modify known field and re-encode
    message.displayName = "Updated"
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let encodedData = try encoder.encode(message)

    // Decode again to verify round-trip preservation
    let roundTripped = try decoder.decode(SampleMessage.self, from: encodedData)
    #expect(roundTripped == message)
    #expect(roundTripped.displayName == "Updated")
    #expect(roundTripped._unknownFields == message._unknownFields)
  }

  @Test("Missing nested message decodes to default with empty unknown fields")
  func decodeMissingNestedMessage() throws {
    let decoder = _ProtoJSONDecoder()
    let wrapper = try decoder.decode(WrapperMessage.self, from: Data("{}".utf8))
    #expect(wrapper.nested == SampleMessage())
    #expect(wrapper.nested._unknownFields.json.isEmpty)
    #expect(wrapper.nested._unknownFields.proto.isEmpty)
  }

  @Test("Protobuf unknown wire bytes round-trip")
  func protobufUnknownBytesRoundTrip() throws {
    // Field 99 (varint wire type 0) = tag (99 << 3) | 0 = 792 = 0x98 0x06, value = 123 (0x7B)
    let rawUnknownBytes = Data([0x98, 0x06, 0x7B])

    var proto = SwiftProtobuf.Google_Protobuf_Empty()
    try proto.merge(serializedBytes: rawUnknownBytes)
    #expect(proto.unknownFields.data == rawUnknownBytes)

    // Simulate conversion from proto to Swift model struct
    var model = SampleMessage()
    model._unknownFields.proto = proto.unknownFields.data

    // Simulate conversion back from Swift model struct to proto
    var reencodedProto = SwiftProtobuf.Google_Protobuf_Empty()
    if !model._unknownFields.proto.isEmpty {
      try reencodedProto.merge(serializedBytes: model._unknownFields.proto)
    }
    #expect(reencodedProto.unknownFields.data == rawUnknownBytes)
  }
}
