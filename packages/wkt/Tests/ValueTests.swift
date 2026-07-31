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
import GoogleCloudWkt
import Testing

@Suite struct ValueTests {
  struct WrappedValue: Codable {
    let value: Value
  }

  @Test("Value default initializer")
  func valueInitDefault() {
    let got = Value()
    #expect(got == .null(NullValue()))
  }

  @Test("Value null initializer")
  func valueInitNull() {
    let got = Value(null: NullValue())
    #expect(got == .null(NullValue()))
  }

  @Test("Value number initializer")
  func valueInitNumber() {
    let got = Value(number: 123.45)
    #expect(got == .number(123.45))
  }

  @Test("Value string initializer")
  func valueInitString() {
    let got = Value(string: "foo")
    #expect(got == .string("foo"))
  }

  @Test("Value bool initializer")
  func valueInitBool() {
    let gotTrue = Value(bool: true)
    #expect(gotTrue == .bool(true))
    let gotFalse = Value(bool: false)
    #expect(gotFalse == .bool(false))
  }

  @Test("Value object initializer")
  func valueInitObject() {
    // Empty dictionary
    #expect(Value(object: [:]) == .object([:]))

    // One value
    #expect(Value(object: ["a": .string("b")]) == .object(["a": .string("b")]))

    // Two values of different types
    let twoValues: [String: Value] = ["a": .number(1), "b": .bool(true)]
    #expect(Value(object: twoValues) == .object(twoValues))

    // One value is null
    #expect(Value(object: ["a": Value()]) == .object(["a": Value()]))
  }

  @Test("Value array initializer")
  func valueInitArray() {
    // Empty array
    #expect(Value(array: []) == .array([]))

    // One value
    #expect(Value(array: [.string("a")]) == .array([.string("a")]))

    // Two values of different types
    #expect(Value(array: [.number(1), .bool(true)]) == .array([.number(1), .bool(true)]))

    // One non-null and one null value
    #expect(Value(array: [.string("a"), Value()]) == .array([.string("a"), Value()]))
  }

  @Test(
    "Value encoding",
    arguments: [
      (Value.null(NullValue()), "{\"value\":null}"),
      (Value.number(123.45), "{\"value\":123.45}"),
      (Value.string("foo"), "{\"value\":\"foo\"}"),
      (Value.bool(true), "{\"value\":true}"),
      (Value.bool(false), "{\"value\":false}"),
      (Value.object(["a": .string("b")]), "{\"value\":{\"a\":\"b\"}}"),
      (Value.array([.number(1), .number(2)]), "{\"value\":[1,2]}"),
    ])
  func encodeValue(value: Value, expected: String) throws {
    let wrapped = WrappedValue(value: value)
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == expected)
  }

  @Test(
    "Value decoding",
    arguments: [
      ("{\"value\":null}", Value()),
      ("{\"value\":123.45}", Value.number(123.45)),
      ("{\"value\":\"foo\"}", Value.string("foo")),
      ("{\"value\":true}", Value.bool(true)),
      ("{\"value\":false}", Value.bool(false)),
      ("{\"value\":{\"a\":\"b\"}}", Value.object(["a": .string("b")])),
      ("{\"value\":[1,2]}", Value.array([.number(1), .number(2)])),
    ])
  func decodeValue(json: String, expected: Value) throws {
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    let got = try decoder.decode(WrappedValue.self, from: data)
    #expect(got.value == expected)
  }

  @Test(
    "Unpack Value from Any",
    arguments: [
      (#""value":null"#, Value()),
      (#""value":123.45"#, Value.number(123.45)),
      (#""value":"foo""#, Value.string("foo")),
      (#""value":true"#, Value.bool(true)),
      (#""value":false"#, Value.bool(false)),
      (#""value":{"a":"b"}"#, Value.object(["a": .string("b")])),
      (#""value":[1,2]"#, Value.array([.number(1), .number(2)])),
    ])
  func valueAnyUnpack(fragment: String, want: Value) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.Value"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try Value(fromAny: any)
    #expect(got == want)
  }

  @Test func valueAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try Value(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack Value into Any",
    arguments: [
      (Value.null(NullValue()), #""value":null"#),
      (Value.number(123.45), #""value":123.45"#),
      (Value.string("foo"), #""value":"foo""#),
      (Value.bool(true), #""value":true"#),
      (Value.bool(false), #""value":false"#),
      (Value.object(["a": .string("b")]), #""value":{"a":"b"}"#),
      (Value.array([.number(1), .number(2)]), #""value":[1,2]"#),
    ])
  func valueAnyPack(input: Value, fragment: String) throws {
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
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
        ["a": Value(number: 123.45), "b": Value(string: "foo")]
      ),
    ])
  func structAnyUnpack(fragment: String, want: Struct) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.Struct"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try Struct(fromAny: any)
    #expect(got == want)
  }

  @Test func structAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try Struct(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack Struct into Any",
    arguments: [
      (#""value":{}"#, [:]),
      (
        #""value":{"a":123.45,"b":"foo"}"#,
        ["a": Value(number: 123.45), "b": Value(string: "foo")]
      ),
    ])
  func structAnyPack(fragment: String, input: Struct) throws {
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
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
        [Value(string: "a"), Value(number: 123.45), Value(string: "b")]
      ),
    ])
  func listValueAnyUnpack(fragment: String, want: ListValue) throws {
    let expectedUrl = "type.googleapis.com/google.protobuf.ListValue"
    let jsonString = "{\"content\":{\"@type\":\"\(expectedUrl)\",\(fragment)}}"
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    #expect(any.typeUrl == expectedUrl)

    let got = try ListValue(fromAny: any)
    #expect(got == want)
  }

  @Test func listValueAnyUnpackMismatchedUrl() throws {
    let jsonString = #"{"content":{"@type":"bad","value":"unused"}}"#
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    let wrapped = try decoder.decode(AnyTests.WrappedAny.self, from: data)
    let any = wrapped.content
    let error = #expect(throws: AnyError.self) {
      let _ = try ListValue(fromAny: any)
    }
    #expect(error == .mismatchedTypeUrl)
  }

  @Test(
    "Pack ListValue into Any",
    arguments: [
      (#""value":[]"#, []),
      (
        #""value":["a",123.45,"b"]"#,
        [Value(string: "a"), Value(number: 123.45), Value(string: "b")]
      ),
    ])
  func listValueAnyPack(fragment: String, input: ListValue) throws {
    let any = try `Any`(fromMessage: input)
    let wrapped = AnyTests.WrappedAny(content: any)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!

    let want =
      "{\"content\":{\"@type\":\"type.googleapis.com/google.protobuf.ListValue\",\(fragment)}}"
    #expect(got == want)
  }

  struct WrappedNull: Codable {
    let value: NullValue
  }

  @Test("NullValue decoding")
  func decodeNullValue() throws {
    let json = "{\"value\": null}"
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    let got = try decoder.decode(WrappedNull.self, from: data)
    #expect(got.value == NullValue())
  }

  @Test("NullValue decoding failure", arguments: ["{\"value\": 123}", "{\"value\": \"foo\"}"])
  func decodeNullValueFailure(json: String) throws {
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    #expect(throws: (any Error).self) {
      _ = try decoder.decode(WrappedNull.self, from: data)
    }
  }

  @Test("NullValue encoding")
  func encodeNullValue() throws {
    let wrapped = WrappedNull(value: NullValue())
    let encoder = JSONEncoder()
    let data = try encoder.encode(wrapped)
    let got = String(data: data, encoding: .utf8)!
    #expect(got == "{\"value\":null}")
  }
}
