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

@Suite struct WKTStructCodableTests {
  typealias RequiredPrimitives = ProtoJSONDecoderTest.RequiredPrimitives
  typealias OptionalPrimitives = ProtoJSONDecoderTest.OptionalPrimitives
  typealias RepeatedPrimitives = ProtoJSONDecoderTest.RepeatedPrimitives
  typealias MapPrimitives = ProtoJSONDecoderTest.MapPrimitives
  typealias MessageWithRepeated = ProtoJSONDecoderTest.MessageWithRepeated
  typealias CollectionModel = ProtoJSONEncoderTest.CollectionModel

  struct AllPrimitivesMessage: Codable, Equatable, _AnyPackable, Sendable {
    var boolVal: Bool = false
    var intVal: Int = 0
    var int32Val: Int32 = 0
    var int64Val: Int64 = 0
    var uintVal: UInt = 0
    var uint32Val: UInt32 = 0
    var uint64Val: UInt64 = 0
    var floatVal: Float = 0
    var doubleVal: Double = 0
    var stringVal: String = ""
    var dataVal: Data = Data()

    static var _anyTypeUrl: String { "type.googleapis.com/test.AllPrimitivesMessage" }

    init(
      boolVal: Bool = false,
      intVal: Int = 0,
      int32Val: Int32 = 0,
      int64Val: Int64 = 0,
      uintVal: UInt = 0,
      uint32Val: UInt32 = 0,
      uint64Val: UInt64 = 0,
      floatVal: Float = 0,
      doubleVal: Double = 0,
      stringVal: String = "",
      dataVal: Data = Data()
    ) {
      self.boolVal = boolVal
      self.intVal = intVal
      self.int32Val = int32Val
      self.int64Val = int64Val
      self.uintVal = uintVal
      self.uint32Val = uint32Val
      self.uint64Val = uint64Val
      self.floatVal = floatVal
      self.doubleVal = doubleVal
      self.stringVal = stringVal
      self.dataVal = dataVal
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  @Test(arguments: AnyCodingMode.allCases)
  func packAndUnpackAllPrimitives(mode: AnyCodingMode) throws {
    let original = AllPrimitivesMessage(
      boolVal: true,
      intVal: -42,
      int32Val: -32,
      int64Val: Int64.min,
      uintVal: 42,
      uint32Val: 32,
      uint64Val: UInt64.max,
      floatVal: 3.14,
      doubleVal: 2.718281828,
      stringVal: "hello world",
      dataVal: Data([0x01, 0x02, 0x03, 0xFF])
    )

    let packed = try mode.serialize(original)
    #expect(packed["boolVal"] == .bool(true))
    #expect(packed["intVal"] == .number(-42))
    #expect(packed["int32Val"] == .number(-32))
    #expect(packed["int64Val"] == .string(String(Int64.min)))
    #expect(packed["uintVal"] == .number(42))
    #expect(packed["uint32Val"] == .number(32))
    #expect(packed["uint64Val"] == .string(String(UInt64.max)))
    #expect(packed["doubleVal"] == .number(2.718281828))
    #expect(packed["stringVal"] == .string("hello world"))
    #expect(packed["dataVal"] == .string(Data([0x01, 0x02, 0x03, 0xFF]).base64EncodedString()))

    let any = try mode.pack(original)
    let unpacked = try mode.deserialize(AllPrimitivesMessage.self, from: any)
    #expect(unpacked == original)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func packAndUnpackNonConformingFloats(mode: AnyCodingMode) throws {
    let infMsg = AllPrimitivesMessage(floatVal: .infinity, doubleVal: -.infinity)
    let infPacked = try mode.serialize(infMsg)
    #expect(infPacked["floatVal"] == .string("Infinity"))
    #expect(infPacked["doubleVal"] == .string("-Infinity"))

    let infAny = try mode.pack(infMsg)
    let infUnpacked = try mode.deserialize(AllPrimitivesMessage.self, from: infAny)
    #expect(infUnpacked == infMsg)

    let nanMsg = AllPrimitivesMessage(floatVal: .nan, doubleVal: .nan)
    let nanPacked = try mode.serialize(nanMsg)
    #expect(nanPacked["floatVal"] == .string("NaN"))
    #expect(nanPacked["doubleVal"] == .string("NaN"))

    let nanAny = try mode.pack(nanMsg)
    let nanUnpacked = try mode.deserialize(AllPrimitivesMessage.self, from: nanAny)
    #expect(nanUnpacked.floatVal.isNaN)
    #expect(nanUnpacked.doubleVal.isNaN)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeFlexibleStringAndNumericRepresentations(mode: AnyCodingMode) throws {
    let fields: WKTStruct = [
      "boolVal": .string("true"),
      "intVal": .string("-42"),
      "int32Val": .string("-32"),
      "int64Val": .number(64),
      "uintVal": .string("42"),
      "uint32Val": .string("32"),
      "uint64Val": .number(128),
      "floatVal": .string("1.5"),
      "doubleVal": .string("2.5"),
      "stringVal": .string("text"),
      "dataVal": .string(Data("abc".utf8).base64EncodedString()),
    ]
    let any = try AnyCodingMode.makeAny(for: AllPrimitivesMessage.self, fields: fields)
    let decoded = try mode.deserialize(AllPrimitivesMessage.self, from: any)
    #expect(decoded.boolVal == true)
    #expect(decoded.intVal == -42)
    #expect(decoded.int32Val == -32)
    #expect(decoded.int64Val == 64)
    #expect(decoded.uintVal == 42)
    #expect(decoded.uint32Val == 32)
    #expect(decoded.uint64Val == 128)
    #expect(decoded.floatVal == 1.5)
    #expect(decoded.doubleVal == 2.5)
    #expect(decoded.stringVal == "text")
    #expect(decoded.dataVal == Data("abc".utf8))
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeMissingFieldsDefaultsToZeroValues(mode: AnyCodingMode) throws {
    let any = try AnyCodingMode.makeAny(for: AllPrimitivesMessage.self, fields: [:])
    let decoded = try mode.deserialize(AllPrimitivesMessage.self, from: any)
    #expect(decoded == AllPrimitivesMessage())
  }

  struct CollectionsAndOptionalsMessage: Codable, Equatable, _AnyPackable, Sendable {
    var optInt64: Int64? = nil
    var optUInt64: UInt64? = nil
    var optString: String? = nil
    var optData: Data? = nil
    var listInt64: [Int64] = []
    var mapInt64: [String: Int64] = [:]
    var structField: WKTStruct? = nil
    var listValueField: WKTListValue? = nil
    var valueField: WKTValue? = nil

    static var _anyTypeUrl: String { "type.googleapis.com/test.CollectionsAndOptionalsMessage" }

    enum CodingKeys: String, CodingKey {
      case optInt64
      case optUInt64
      case optString
      case optData
      case listInt64
      case mapInt64
      case structField
      case listValueField
      case valueField
    }

    init(
      optInt64: Int64? = nil,
      optUInt64: UInt64? = nil,
      optString: String? = nil,
      optData: Data? = nil,
      listInt64: [Int64] = [],
      mapInt64: [String: Int64] = [:],
      structField: WKTStruct? = nil,
      listValueField: WKTListValue? = nil,
      valueField: WKTValue? = nil
    ) {
      self.optInt64 = optInt64
      self.optUInt64 = optUInt64
      self.optString = optString
      self.optData = optData
      self.listInt64 = listInt64
      self.mapInt64 = mapInt64
      self.structField = structField
      self.listValueField = listValueField
      self.valueField = valueField
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.optInt64 = try container.decodeIfPresent(Int64.self, forKey: .optInt64)
      self.optUInt64 = try container.decodeIfPresent(UInt64.self, forKey: .optUInt64)
      self.optString = try container.decodeIfPresent(String.self, forKey: .optString)
      self.optData = try container.decodeIfPresent(Data.self, forKey: .optData)
      if let v = try container.decodeIfPresent([Int64].self, forKey: .listInt64) {
        self.listInt64 = v
      }
      if let v = try container.decodeIfPresent([String: Int64].self, forKey: .mapInt64) {
        self.mapInt64 = v
      }
      self.structField = try container.decodeIfPresent(WKTStruct.self, forKey: .structField)
      self.listValueField = try container.decodeIfPresent(
        WKTListValue.self, forKey: .listValueField)
      self.valueField = try container.decodeIfPresent(WKTValue.self, forKey: .valueField)
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(self.optInt64, forKey: .optInt64)
      try container.encodeIfPresent(self.optUInt64, forKey: .optUInt64)
      try container.encodeIfPresent(self.optString, forKey: .optString)
      try container.encodeIfPresent(self.optData, forKey: .optData)
      try container.encode(self.listInt64, forKey: .listInt64)
      try container.encode(self.mapInt64, forKey: .mapInt64)
      try container.encodeIfPresent(self.structField, forKey: .structField)
      try container.encodeIfPresent(self.listValueField, forKey: .listValueField)
      try container.encodeIfPresent(self.valueField, forKey: .valueField)
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  @Test(arguments: AnyCodingMode.allCases)
  func omitEmptyCollectionsAndPreserveExplicitOptionalWKTCollections(mode: AnyCodingMode) throws {
    let emptyMsg = CollectionsAndOptionalsMessage()
    let emptyPacked = try mode.serialize(emptyMsg)
    #expect(emptyPacked.isEmpty)

    let presentEmptyWKT = CollectionsAndOptionalsMessage(
      structField: [:],
      listValueField: []
    )
    let presentPacked = try mode.serialize(presentEmptyWKT)
    #expect(presentPacked == ["structField": .object([:]), "listValueField": .array([])])
    let any = try mode.pack(presentEmptyWKT)
    let unpacked = try mode.deserialize(CollectionsAndOptionalsMessage.self, from: any)
    #expect(unpacked == presentEmptyWKT)

    let populated = CollectionsAndOptionalsMessage(
      optInt64: 9_000_000_000,
      optUInt64: 18_000_000_000,
      optString: "present",
      optData: Data([0xAA, 0xBB]),
      listInt64: [1, 2, Int64.max],
      mapInt64: ["k": Int64.min],
      structField: ["nested": .bool(true)],
      listValueField: [.number(1), .string("two")],
      valueField: .string("val")
    )
    let popPacked = try mode.serialize(populated)
    #expect(popPacked["optInt64"] == .string("9000000000"))
    #expect(popPacked["optUInt64"] == .string("18000000000"))
    #expect(
      popPacked["listInt64"] == .array([.string("1"), .string("2"), .string(String(Int64.max))]))
    #expect(popPacked["mapInt64"] == .object(["k": .string(String(Int64.min))]))

    let popAny = try mode.pack(populated)
    let popUnpacked = try mode.deserialize(CollectionsAndOptionalsMessage.self, from: popAny)
    #expect(popUnpacked == populated)
  }

  @Test func preserveEmptyCollectionsWhenDisabled() throws {
    let encoder = WKTStructEncoder(omitEmptyCollections: false)
    let msg = CollectionsAndOptionalsMessage()
    let packed = try encoder.encode(msg)
    #expect(packed["listInt64"] == .array([]))
    #expect(packed["mapInt64"] == .object([:]))
  }

  struct NestedAndSuperCodableMessage: Codable, Equatable, _AnyPackable, Sendable {
    static var _anyTypeUrl: String { "type.googleapis.com/test.NestedAndSuperCodableMessage" }

    var nestedDictValue: String
    var nestedArrayValues: [Int32]
    var superValue: String

    enum CodingKeys: String, CodingKey {
      case nestedDict
      case nestedArray
      case customSuper
    }

    enum NestedKeys: String, CodingKey {
      case value
      case secondValue
    }

    init(nestedDictValue: String, nestedArrayValues: [Int32], superValue: String) {
      self.nestedDictValue = nestedDictValue
      self.nestedArrayValues = nestedArrayValues
      self.superValue = superValue
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let nestedDict = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nestedDict)
      self.nestedDictValue = try nestedDict.decode(String.self, forKey: .value)
      let secondVal = try nestedDict.decode(String.self, forKey: .secondValue)
      #expect(secondVal == "second")

      var nestedArr = try container.nestedUnkeyedContainer(forKey: .nestedArray)
      var items: [Int32] = []
      while !nestedArr.isAtEnd {
        items.append(try nestedArr.decode(Int32.self))
      }
      self.nestedArrayValues = items

      let superDec = try container.superDecoder(forKey: .customSuper)
      self.superValue = try String(from: superDec)
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      var nestedDict1 = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nestedDict)
      try nestedDict1.encode(self.nestedDictValue, forKey: .value)
      var nestedDict2 = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nestedDict)
      try nestedDict2.encode("second", forKey: .secondValue)

      var nestedArr = container.nestedUnkeyedContainer(forKey: .nestedArray)
      for item in self.nestedArrayValues {
        try nestedArr.encode(item)
      }

      let superEnc = container.superEncoder(forKey: .customSuper)
      try self.superValue.encode(to: superEnc)
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  @Test(arguments: AnyCodingMode.allCases)
  func nestedContainersAndSuperEncoderDecoder(mode: AnyCodingMode) throws {
    let original = NestedAndSuperCodableMessage(
      nestedDictValue: "inside",
      nestedArrayValues: [10, 20, 30],
      superValue: "super-val"
    )
    let encoded = try mode.serialize(original)
    #expect(
      encoded == [
        "nestedDict": .object(["value": .string("inside"), "secondValue": .string("second")]),
        "nestedArray": .array([.number(10), .number(20), .number(30)]),
        "customSuper": .string("super-val"),
      ]
    )

    let any = try mode.pack(original)
    let decoded = try mode.deserialize(NestedAndSuperCodableMessage.self, from: any)
    #expect(decoded == original)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func invalidWKTValueNumberThrowsEncodingError(mode: AnyCodingMode) throws {
    let msg = CollectionsAndOptionalsMessage(valueField: .number(.nan))
    #expect(throws: EncodingError.self) {
      _ = try mode.serialize(msg)
    }
    let nestedBadStruct = CollectionsAndOptionalsMessage(structField: ["bad": .number(.infinity)])
    #expect(throws: EncodingError.self) {
      _ = try mode.serialize(nestedBadStruct)
    }
    let nestedBadList = CollectionsAndOptionalsMessage(listValueField: [.number(-.infinity)])
    #expect(throws: EncodingError.self) {
      _ = try mode.serialize(nestedBadList)
    }
  }

  struct RecursiveNode: Codable, Equatable, _AnyPackable, Sendable {
    var name: String = ""
    var child: WKTRecursive<RecursiveNode>? = nil

    static var _anyTypeUrl: String { "type.googleapis.com/test.RecursiveNode" }

    init(name: String = "", child: WKTRecursive<RecursiveNode>? = nil) {
      self.name = name
      self.child = child
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  @Test(arguments: AnyCodingMode.allCases)
  func recursiveMessagePackAndUnpack(mode: AnyCodingMode) throws {
    let leaf = RecursiveNode(name: "leaf")
    let root = RecursiveNode(name: "root", child: WKTRecursive(value: leaf))

    let any = try mode.pack(root)
    let unpacked = try mode.deserialize(RecursiveNode.self, from: any)
    #expect(unpacked == root)
    #expect(unpacked.child?.value.name == "leaf")
  }

  @Test func topLevelNonObjectThrowsEncodingError() {
    let encoder = WKTStructEncoder()
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode("not-an-object")
    }
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode([1, 2, 3])
    }
  }

  @Test func directWKTStructAndValueDecodeFastPath() throws {
    let decoder = WKTStructDecoder()
    let input: WKTStruct = ["a": .string("hello"), "b": .number(123)]
    let decodedStruct = try decoder.decode(WKTStruct.self, from: input)
    #expect(decodedStruct == input)
    let decodedValue = try decoder.decode(WKTValue.self, from: input)
    #expect(decodedValue == .object(input))
  }

  @Test(
    "required primitives",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.requiredInputs
  )
  func requiredPrimitives(mode: AnyCodingMode, testCase: (String, RequiredPrimitives)) throws {
    let (input, want) = testCase
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: RequiredPrimitives.self)
    let got = try mode.deserialize(RequiredPrimitives.self, from: any)
    #expect(got == want)

    let repackedAny = try mode.pack(want)
    let unpacked = try mode.deserialize(RequiredPrimitives.self, from: repackedAny)
    #expect(unpacked == want)
  }

  @Test(
    "required bad inputs",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.requiredBadInputs
  )
  func requiredPrimitivesBadInputs(mode: AnyCodingMode, input: String) throws {
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: RequiredPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(RequiredPrimitives.self, from: any)
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test(arguments: AnyCodingMode.allCases)
  func requiredPrimitivesBadString(mode: AnyCodingMode) throws {
    let any = try AnyCodingMode.makeAny(
      jsonObject: #"{"fieldString": 42 }"#, for: RequiredPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(RequiredPrimitives.self, from: any)
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }

  @Test(
    "optional primitives",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.optionalInputs
  )
  func optionalPrimitives(mode: AnyCodingMode, testCase: (String, OptionalPrimitives)) throws {
    let (input, want) = testCase
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: OptionalPrimitives.self)
    let got = try mode.deserialize(OptionalPrimitives.self, from: any)
    #expect(got == want)

    let repackedAny = try mode.pack(want)
    let unpacked = try mode.deserialize(OptionalPrimitives.self, from: repackedAny)
    #expect(unpacked == want)
  }

  @Test(
    "optional bad inputs",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.optionalBadInputs
  )
  func optionalPrimitivesBadInputs(mode: AnyCodingMode, input: String) throws {
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: OptionalPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(OptionalPrimitives.self, from: any)
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test(arguments: AnyCodingMode.allCases)
  func optionalPrimitivesBadString(mode: AnyCodingMode) throws {
    let any = try AnyCodingMode.makeAny(
      jsonObject: #"{"fieldString": 42 }"#, for: OptionalPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(OptionalPrimitives.self, from: any)
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }

  @Test(
    "repeated primitives",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.repeatedInputs
  )
  func repeatedPrimitives(mode: AnyCodingMode, testCase: (String, RepeatedPrimitives)) throws {
    let (input, want) = testCase
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: RepeatedPrimitives.self)
    let got = try mode.deserialize(RepeatedPrimitives.self, from: any)
    #expect(got == want)

    let repackedAny = try mode.pack(want)
    let unpacked = try mode.deserialize(RepeatedPrimitives.self, from: repackedAny)
    #expect(unpacked == want)
  }

  @Test(
    "repeated bad inputs",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.repeatedBadInputs
  )
  func repeatedPrimitivesBadInputs(mode: AnyCodingMode, input: String) throws {
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: RepeatedPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(RepeatedPrimitives.self, from: any)
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test(arguments: AnyCodingMode.allCases)
  func repeatedPrimitivesBadString(mode: AnyCodingMode) throws {
    let any = try AnyCodingMode.makeAny(
      jsonObject: #"{"fieldData": [42] }"#, for: RepeatedPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(RepeatedPrimitives.self, from: any)
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }

  @Test(
    "map primitives",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.mapInputs
  )
  func mapPrimitives(mode: AnyCodingMode, testCase: (String, MapPrimitives)) throws {
    let (input, want) = testCase
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: MapPrimitives.self)
    let got = try mode.deserialize(MapPrimitives.self, from: any)
    #expect(got == want)

    let repackedAny = try mode.pack(want)
    let unpacked = try mode.deserialize(MapPrimitives.self, from: repackedAny)
    #expect(unpacked == want)
  }

  @Test(
    "map bad inputs",
    arguments: AnyCodingMode.allCases,
    ProtoJSONDecoderTest.mapBadInputs
  )
  func mapPrimitivesBadInputs(mode: AnyCodingMode, input: String) throws {
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: MapPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(MapPrimitives.self, from: any)
    }
    #expect({ if case .dataCorrupted = error { true } else { false } }())
  }

  @Test(arguments: AnyCodingMode.allCases)
  func mapPrimitivesBadString(mode: AnyCodingMode) throws {
    let any = try AnyCodingMode.makeAny(
      jsonObject: #"{"fieldData": {"a": 42} }"#, for: MapPrimitives.self)
    let error = #expect(throws: DecodingError.self) {
      _ = try mode.deserialize(MapPrimitives.self, from: any)
    }
    #expect({ if case .typeMismatch = error { true } else { false } }())
  }

  @Test(arguments: AnyCodingMode.allCases)
  func decodeMissingMapNested(mode: AnyCodingMode) throws {
    let input = #"{"repeatedMessage": [{}, {}]}"#
    let any = try AnyCodingMode.makeAny(jsonObject: input, for: MessageWithRepeated.self)
    let want = MessageWithRepeated(repeatedMessage: [MapPrimitives(), MapPrimitives()])
    let got = try mode.deserialize(MessageWithRepeated.self, from: any)
    #expect(got == want)

    let repackedAny = try mode.pack(want)
    let unpacked = try mode.deserialize(MessageWithRepeated.self, from: repackedAny)
    #expect(unpacked == want)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func collectionModelOmitEmptyAndPreserveMatrix(mode: AnyCodingMode) throws {
    let model = CollectionModel()
    let packed = try mode.serialize(model)
    #expect(
      packed == [
        "name": .string("test"),
        "populatedList": .array([.string("a"), .string("b")]),
        "populatedMap": .object(["k": .string("v")]),
        "matrix": .array([.array([]), .array([.number(1), .number(2)])]),
      ]
    )

    let any = try mode.pack(model)
    let unpacked = try mode.deserialize(CollectionModel.self, from: any)
    #expect(unpacked == model)
  }

  @Test(arguments: AnyCodingMode.allCases)
  func allGeneratedWKTMessages(mode: AnyCodingMode) throws {
    let sourceContext = WKTSourceContext().with {
      $0.fileName = "google/protobuf/type.proto"
    }
    let option = WKTOption().with {
      $0.name = "deprecated"
      $0.value = try? WKTAny(fromMessage: true)
    }
    let enumValue = WKTEnumValue().with {
      $0.name = "ENUM_VALUE_ONE"
      $0.number = 1
      $0.options = [option]
    }
    let wktEnum = WKTEnum().with {
      $0.name = "SampleEnum"
      $0.enumvalue = [enumValue]
      $0.options = [option]
      $0.sourceContext = sourceContext
      $0.syntax = .proto3
      $0.edition = "2023"
    }
    let field = WKTField().with {
      $0.kind = .typeMessage
      $0.cardinality = .repeated
      $0.number = 2
      $0.name = "items"
      $0.typeUrl = "type.googleapis.com/google.protobuf.Value"
      $0.oneofIndex = 1
      $0.packed = true
      $0.options = [option]
      $0.jsonName = "items"
      $0.defaultValue = ""
    }
    let wktType = WKTType().with {
      $0.name = "SampleType"
      $0.fields = [field]
      $0.oneofs = ["choice"]
      $0.options = [option]
      $0.sourceContext = sourceContext
      $0.syntax = .proto3
      $0.edition = "2023"
    }
    let method = WKTMethod().with {
      $0.name = "ListItems"
      $0.requestTypeUrl = "type.googleapis.com/google.protobuf.Empty"
      $0.requestStreaming = false
      $0.responseTypeUrl = "type.googleapis.com/google.protobuf.Struct"
      $0.responseStreaming = true
      $0.options = [option]
      $0.syntax = .proto3
    }
    let mixin = WKTMixin().with {
      $0.name = "google.cloud.location.Locations"
      $0.root = "google.cloud.location"
    }
    var api = WKTApi().with {
      $0.name = "google.example.Service"
      $0.methods = [method]
      $0.options = [option]
      $0.version = "v1"
      $0.sourceContext = sourceContext
      $0.mixins = [mixin]
      $0.syntax = .proto3
    }
    api._unknownFields.json = [
      "extraStr": .string("extra"),
      "extraObj": .object(["inner": .number(42)]),
      "extraArr": .array([.bool(true), .null(WKTNullValue())]),
    ]

    func verifyRoundTrip<M: Codable & Equatable & _AnyPackable>(_ message: M) throws {
      let any = try mode.pack(message)
      let unpacked = try mode.deserialize(M.self, from: any)
      #expect(unpacked == message)

      #expect(throws: WKTAnyError.mismatchedTypeURL) {
        let wrongAny = try AnyCodingMode.makeAny(for: AllPrimitivesMessage.self, fields: [:])
        _ = try mode.deserialize(M.self, from: wrongAny)
      }
    }

    try verifyRoundTrip(sourceContext)
    try verifyRoundTrip(option)
    try verifyRoundTrip(enumValue)
    try verifyRoundTrip(wktEnum)
    try verifyRoundTrip(field)
    try verifyRoundTrip(wktType)
    try verifyRoundTrip(method)
    try verifyRoundTrip(mixin)
    try verifyRoundTrip(api)
  }

  struct NestedCustomWKTMessage: Codable, Equatable, _AnyPackable, Sendable {
    static var _anyTypeUrl: String { "type.googleapis.com/test.NestedCustomWKTMessage" }

    var timestamp: WKTTimestamp? = nil
    var duration: WKTDuration? = nil
    var fieldMask: WKTFieldMask? = nil
    var empty: WKTEmpty? = nil

    init(
      timestamp: WKTTimestamp? = nil,
      duration: WKTDuration? = nil,
      fieldMask: WKTFieldMask? = nil,
      empty: WKTEmpty? = nil
    ) {
      self.timestamp = timestamp
      self.duration = duration
      self.fieldMask = fieldMask
      self.empty = empty
    }

    init(fromAny any: WKTAny) throws {
      self = try _anyDeserialize(Self.self, from: any)
    }

    func _pack() throws -> WKTStruct {
      return try _anySerialize(message: self)
    }
  }

  @Test(arguments: AnyCodingMode.allCases)
  func nestedCustomWKTMessages(mode: AnyCodingMode) throws {
    let message = NestedCustomWKTMessage(
      timestamp: try WKTTimestamp(seconds: 1_700_000_000, nanos: 123_456_789),
      duration: try WKTDuration(seconds: 60, nanos: 500_000_000),
      fieldMask: WKTFieldMask(paths: ["user.display_name", "photo"]),
      empty: WKTEmpty()
    )
    let packed = try mode.serialize(message)
    #expect(packed["timestamp"] == .string("2023-11-14T22:13:20.123456789Z"))
    #expect(packed["duration"] == .string("60.500s"))
    #expect(packed["fieldMask"] == .string("user.displayName,photo"))
    #expect(packed["empty"] == .object([:]))

    let any = try mode.pack(message)
    let unpacked = try mode.deserialize(NestedCustomWKTMessage.self, from: any)
    #expect(unpacked == message)
  }
}
