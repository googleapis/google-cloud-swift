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
@testable @_spi(GoogleCloudInternal) import GoogleWKT

enum AnyCodingMode: String, CaseIterable, Sendable, CustomTestStringConvertible {
  case slow
  case fast

  var testDescription: String { self.rawValue }

  func serialize<M: Encodable>(_ message: M) throws -> WKTStruct {
    switch self {
    case .slow:
      return try _slowAnySerialize(message: message)
    case .fast:
      return try _anySerialize(message: message)
    }
  }

  func deserialize<M: Decodable & _AnyPackable>(_ type: M.Type, from any: WKTAny) throws -> M {
    switch self {
    case .slow:
      return try _slowAnyDeserialize(type, from: any)
    case .fast:
      return try _anyDeserialize(type, from: any)
    }
  }

  func pack<M: Encodable & _AnyPackable>(_ message: M) throws -> WKTAny {
    let fields = try self.serialize(message)
    return try Self.makeAny(for: M.self, fields: fields)
  }

  static func makeAny<M: _AnyPackable>(for type: M.Type, fields: WKTStruct) throws -> WKTAny {
    var fieldsWithType = fields
    fieldsWithType["@type"] = .string(M._anyTypeUrl)
    return try WKTStructDecoder().decode(WKTAny.self, from: fieldsWithType)
  }

  static func makeAny<M: _AnyPackable>(jsonObject: String, for type: M.Type) throws -> WKTAny {
    let decoder = _ProtoJSONDecoder()
    let fields = try decoder.decode(WKTStruct.self, from: Data(jsonObject.utf8))
    return try Self.makeAny(for: type, fields: fields)
  }
}

extension WKTAnyTests {
  struct BasicMessage: Codable, Equatable, Sendable {
    let field0: String
    let field1: String
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeBasicMessage(mode: AnyCodingMode) throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/test.BasicMessage","field0":"0","field1":"1"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeURL == "type.googleapis.com/test.BasicMessage")

    let inner = try mode.deserialize(BasicMessage.self, from: any)
    #expect(inner == BasicMessage(field0: "0", field1: "1"))
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeBasicMessageMismatchedUrl(mode: AnyCodingMode) throws {
    let jsonString =
      #"{"content":{"@type":"bad","field0":"0","field1":"1"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try mode.deserialize(BasicMessage.self, from: any)
    }
    #expect(error == .mismatchedTypeURL)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeBasicMessageMissing(mode: AnyCodingMode) throws {
    let jsonString =
      #"{"content":{"@type":"type.googleapis.com/test.BasicMessage","field0":"0"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeURL == "type.googleapis.com/test.BasicMessage")

    let inner = try mode.deserialize(BasicMessage.self, from: any)
    #expect(inner == BasicMessage(field0: "0", field1: ""))
  }

  @Test(arguments: AnyCodingMode.allCases)
  func encodeBasicMessage(mode: AnyCodingMode) throws {
    let message = BasicMessage(field0: "0", field1: "1")
    let packed = try mode.serialize(message)
    #expect(packed == ["field0": .string("0"), "field1": .string("1")])
  }
}

extension WKTAnyTests.BasicMessage: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/test.BasicMessage"
  }

  public init(fromAny any: WKTAny) throws {
    self = try GoogleWKT._slowAnyDeserialize(Self.self, from: any)
  }

  public func _pack() throws -> WKTStruct {
    return try GoogleWKT._slowAnySerialize(message: self)
  }
}
