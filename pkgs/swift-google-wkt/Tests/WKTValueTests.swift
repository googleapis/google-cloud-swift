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
@_spi(GoogleCloudInternal) import GoogleWKT
import Testing

@Suite struct WKTValueTests {
  struct WrappedValue: Codable {
    let value: WKTValue
  }

  @Test("Value default initializer")
  func valueInitDefault() {
    let got = WKTValue()
    #expect(got == .null(WKTNullValue()))
  }

  @Test("Value null initializer")
  func valueInitNull() {
    let got = WKTValue(null: WKTNullValue())
    #expect(got == .null(WKTNullValue()))
  }

  @Test("Value number initializer")
  func valueInitNumber() {
    let got = WKTValue(number: 123.45)
    #expect(got == .number(123.45))
  }

  @Test("Value string initializer")
  func valueInitString() {
    let got = WKTValue(string: "foo")
    #expect(got == .string("foo"))
  }

  @Test("Value bool initializer")
  func valueInitBool() {
    let gotTrue = WKTValue(bool: true)
    #expect(gotTrue == .bool(true))
    let gotFalse = WKTValue(bool: false)
    #expect(gotFalse == .bool(false))
  }

  @Test("Value object initializer")
  func valueInitObject() {
    // Empty dictionary
    #expect(WKTValue(object: [:]) == .object([:]))

    // One value
    #expect(WKTValue(object: ["a": .string("b")]) == .object(["a": .string("b")]))

    // Two values of different types
    let twoValues: [String: WKTValue] = ["a": .number(1), "b": .bool(true)]
    #expect(WKTValue(object: twoValues) == .object(twoValues))

    // One value is null
    #expect(WKTValue(object: ["a": WKTValue()]) == .object(["a": WKTValue()]))
  }

  @Test("Value array initializer")
  func valueInitArray() {
    // Empty array
    #expect(WKTValue(array: []) == .array([]))

    // One value
    #expect(WKTValue(array: [.string("a")]) == .array([.string("a")]))

    // Two values of different types
    #expect(WKTValue(array: [.number(1), .bool(true)]) == .array([.number(1), .bool(true)]))

    // One non-null and one null value
    #expect(WKTValue(array: [.string("a"), WKTValue()]) == .array([.string("a"), WKTValue()]))
  }

  @Test(
    "Value encoding",
    arguments: [
      (WKTValue.null(WKTNullValue()), "{\"value\":null}"),
      (WKTValue.number(123.45), "{\"value\":123.45}"),
      (WKTValue.string("foo"), "{\"value\":\"foo\"}"),
      (WKTValue.bool(true), "{\"value\":true}"),
      (WKTValue.bool(false), "{\"value\":false}"),
      (WKTValue.object(["a": .string("b")]), "{\"value\":{\"a\":\"b\"}}"),
      (WKTValue.array([.number(1), .number(2)]), "{\"value\":[1,2]}"),
    ])
  func encodeValue(value: WKTValue, expected: String) throws {
    let wrapped = WrappedValue(value: value)
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == expected)
  }

  @Test(
    "Value decoding",
    arguments: [
      ("{\"value\":null}", WKTValue()),
      ("{\"value\":123.45}", WKTValue.number(123.45)),
      ("{\"value\":\"foo\"}", WKTValue.string("foo")),
      ("{\"value\":\"true\"}", WKTValue.string("true")),
      ("{\"value\":\"false\"}", WKTValue.string("false")),
      ("{\"value\":\"42\"}", WKTValue.string("42")),
      ("{\"value\":\"\"}", WKTValue.string("")),
      ("{\"value\":true}", WKTValue.bool(true)),
      ("{\"value\":false}", WKTValue.bool(false)),
      ("{\"value\":{\"a\":\"b\"}}", WKTValue.object(["a": .string("b")])),
      ("{\"value\":{\"a\":\"true\"}}", WKTValue.object(["a": .string("true")])),
      ("{\"value\":[1,2]}", WKTValue.array([.number(1), .number(2)])),
      (
        "{\"value\":[\"true\",\"false\",true,false,42]}",
        WKTValue.array([.string("true"), .string("false"), .bool(true), .bool(false), .number(42)])
      ),
    ])
  func decodeValue(json: String, expected: WKTValue) throws {
    let data = Data(json.utf8)
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(WrappedValue.self, from: data)
    #expect(got.value == expected)
  }

  struct WrappedStruct: Codable, Equatable {
    let object: WKTStruct
  }

  struct WrappedList: Codable, Equatable {
    let list: WKTListValue
  }

  @Test func decodeProtoJSONStruct() throws {
    let json = #"{"object":{"a":"true","b":true}}"#
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(WrappedStruct.self, from: Data(json.utf8))
    let want = WrappedStruct(object: ["a": .string("true"), "b": .bool(true)])
    #expect(got == want)
  }

  @Test func decodeProtoJSONList() throws {
    let json = #"{"list":["true","false",true,false]}"#
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(WrappedList.self, from: Data(json.utf8))
    let want = WrappedList(list: [.string("true"), .string("false"), .bool(true), .bool(false)])
    #expect(got == want)
  }

  @Test(
    "Value ProtoJSON roundtrip",
    arguments: [
      WKTValue(),
      WKTValue.null(WKTNullValue()),
      WKTValue.number(123.45),
      WKTValue.number(0),
      WKTValue.number(-42),
      WKTValue.string("foo"),
      WKTValue.string("true"),
      WKTValue.string("false"),
      WKTValue.string("42"),
      WKTValue.string(""),
      WKTValue.bool(true),
      WKTValue.bool(false),
      WKTValue.object(["a": .string("true"), "b": .bool(false), "c": .number(42)]),
      WKTValue.array([.string("true"), .bool(true), .null(WKTNullValue()), .number(0)]),
    ])
  func roundtripProtoJSONValue(value: WKTValue) throws {
    let encoder = _ProtoJSONEncoder()
    let decoder = _ProtoJSONDecoder()
    let wrapped = WrappedValue(value: value)
    let data = try encoder.encode(wrapped)
    let decoded = try decoder.decode(WrappedValue.self, from: data)
    #expect(decoded.value == value)
  }

  @Test(
    "Value ProtoJSON top-level roundtrip",
    arguments: [
      WKTValue(),
      WKTValue.null(WKTNullValue()),
      WKTValue.number(123.45),
      WKTValue.number(0),
      WKTValue.number(-42),
      WKTValue.string("foo"),
      WKTValue.string("true"),
      WKTValue.string("false"),
      WKTValue.string("42"),
      WKTValue.string(""),
      WKTValue.bool(true),
      WKTValue.bool(false),
      WKTValue.object(["a": .string("true"), "b": .bool(false), "c": .number(42)]),
      WKTValue.array([.string("true"), .bool(true), .null(WKTNullValue()), .number(0)]),
    ])
  func roundtripTopLevelProtoJSONValue(value: WKTValue) throws {
    let encoder = _ProtoJSONEncoder()
    let decoder = _ProtoJSONDecoder()
    let data = try encoder.encode(value)
    let decoded = try decoder.decode(WKTValue.self, from: data)
    #expect(decoded == value)
  }

  @Test(
    "Unpack Value from Any",
    arguments: [
      (#""value":null"#, WKTValue()),
      (#""value":123.45"#, WKTValue.number(123.45)),
      (#""value":"foo""#, WKTValue.string("foo")),
      (#""value":true"#, WKTValue.bool(true)),
      (#""value":false"#, WKTValue.bool(false)),
      (#""value":{"a":"b"}"#, WKTValue.object(["a": .string("b")])),
      (#""value":[1,2]"#, WKTValue.array([.number(1), .number(2)])),
    ])
  func valueAnyUnpack(fragment: String, want: WKTValue) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.Value"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try WKTValue(fromAny: any)
    #expect(got == want)
  }

  @Test func valueAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTValue(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack Value into Any",
    arguments: [
      (WKTValue.null(WKTNullValue()), #""value":null"#),
      (WKTValue.number(123.45), #""value":123.45"#),
      (WKTValue.string("foo"), #""value":"foo""#),
      (WKTValue.bool(true), #""value":true"#),
      (WKTValue.bool(false), #""value":false"#),
      (WKTValue.object(["a": .string("b")]), #""value":{"a":"b"}"#),
      (WKTValue.array([.number(1), .number(2)]), #""value":[1,2]"#),
    ])
  func valueAnyPack(input: WKTValue, fragment: String) throws {
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      "{\"content\":{\"@type\":\"type.googleapis.com/google.protobuf.Value\",\(fragment)}}"
    #expect(got == want)
  }

  @Test(
    "Unpack Struct from Any",
    arguments: [
      (#""value":{}"#, [:]),
      (
        #""value":{"a":123.45,"b":"foo"}"#,
        ["a": WKTValue(number: 123.45), "b": WKTValue(string: "foo")]
      ),
    ])
  func structAnyUnpack(fragment: String, want: WKTStruct) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.Struct"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try WKTStruct(fromAny: any)
    #expect(got == want)
  }

  @Test func structAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTStruct(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack Struct into Any",
    arguments: [
      (#""value":{}"#, [:]),
      (
        #""value":{"a":123.45,"b":"foo"}"#,
        ["a": WKTValue(number: 123.45), "b": WKTValue(string: "foo")]
      ),
    ])
  func structAnyPack(fragment: String, input: WKTStruct) throws {
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      "{\"content\":{\"@type\":\"type.googleapis.com/google.protobuf.Struct\",\(fragment)}}"
    #expect(got == want)
  }

  @Test(
    "Unpack ListValue from Any",
    arguments: [
      (#""value":[]"#, []),
      (
        #""value":["a",123.45,"b"]"#,
        [WKTValue(string: "a"), WKTValue(number: 123.45), WKTValue(string: "b")]
      ),
    ])
  func listValueAnyUnpack(fragment: String, want: WKTListValue) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.ListValue"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try WKTListValue(fromAny: any)
    #expect(got == want)
  }

  @Test func listValueAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = _ProtoJSONDecoder()
    let wrapped = try decoder.decode(WKTAnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: WKTAnyError.self) {
      let _ = try WKTListValue(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack ListValue into Any",
    arguments: [
      (#""value":[]"#, []),
      (
        #""value":["a",123.45,"b"]"#,
        [WKTValue(string: "a"), WKTValue(number: 123.45), WKTValue(string: "b")]
      ),
    ])
  func listValueAnyPack(fragment: String, input: WKTListValue) throws {
    let any = try WKTAny(fromMessage: input)
    let wrapped = WKTAnyTests.WrappedAny(content: any)
    let encoder = _ProtoJSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      "{\"content\":{\"@type\":\"type.googleapis.com/google.protobuf.ListValue\",\(fragment)}}"
    #expect(got == want)
  }

  struct WrappedNull: Codable {
    let value: WKTNullValue
  }

  @Test("NullValue decoding")
  func decodeNullValue() throws {
    let json = "{\"value\": null}"
    let data = Data(json.utf8)
    let decoder = _ProtoJSONDecoder()
    let got = try decoder.decode(WrappedNull.self, from: data)
    #expect(got.value == WKTNullValue())
  }

  @Test("NullValue decoding failure", arguments: ["{\"value\": 123}", "{\"value\": \"foo\"}"])
  func decodeNullValueFailure(json: String) throws {
    let data = Data(json.utf8)
    let decoder = _ProtoJSONDecoder()
    #expect(throws: (any Error).self) {
      _ = try decoder.decode(WrappedNull.self, from: data)
    }
  }

  @Test("NullValue encoding")
  func encodeNullValue() throws {
    let wrapped = WrappedNull(value: WKTNullValue())
    let encoder = _ProtoJSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{\"value\":null}")
  }

  @Test(
    "Value encoding invalid numbers throws error",
    arguments: [
      WKTValue.number(Double.infinity),
      WKTValue.number(-Double.infinity),
      WKTValue.number(Double.nan),
    ])
  func encodeValueInvalidNumbers(value: WKTValue) throws {
    let encoder = _ProtoJSONEncoder()
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode(value)
    }

    let wrapped = WrappedValue(value: value)
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode(wrapped)
    }
  }

  @Test("Value nested invalid numbers throw error")
  func encodeValueNestedInvalidNumbers() throws {
    let encoder = _ProtoJSONEncoder()
    let objectValue = WKTValue.object(["test": .number(Double.infinity)])
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode(objectValue)
    }

    let arrayValue = WKTValue.array([.number(Double.nan)])
    #expect(throws: EncodingError.self) {
      _ = try encoder.encode(arrayValue)
    }
  }
}
