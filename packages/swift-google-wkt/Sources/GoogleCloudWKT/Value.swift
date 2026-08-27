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

/// Represents a JSON value.
///
/// `Value` represents a dynamically typed value which can be either
/// null, a number, a string, a boolean, a recursive struct value, or a
/// list of values. A producer of value is expected to set one of these
/// variants. Absence of any variant is an invalid state.
public enum Value: Codable, Equatable, Sendable {
  /// Represents a JSON `null`.
  case null(NullValue)

  /// Represents a JSON number. Must not be `NaN`, `Infinity` or
  /// `-Infinity`, since those are not supported in JSON. This also cannot
  /// represent large Int64 values, since JSON format generally does not
  /// support them in its number type.
  case number(Double)

  /// Represents a JSON string.
  case string(String)

  /// Represents a JSON boolean (`true` or `false` literal in JSON).
  case bool(Bool)

  /// Represents a JSON object.
  case object(Struct)

  /// Represents a JSON array.
  case array(ListValue)

  /// Initialize a value to the default: [`null`](doc:Value/null(_:)).
  public init() {
    self = .null(NullValue())
  }

  /// Initialize a value from a ``NullValue``.
  public init(null v: NullValue) {
    self = .null(NullValue())
  }

  /// Initialize a value from a number.
  public init(number v: Double) {
    self = .number(v)
  }

  /// Initialize a value from a string.
  public init(string v: String) {
    self = .string(v)
  }

  /// Initialize a value from a boolean.
  public init(bool v: Bool) {
    self = .bool(v)
  }

  /// Initialize a value from an object.
  public init(object v: Struct) {
    self = .object(v)
  }

  /// Initialize a `Value` with an array.
  public init(array v: ListValue) {
    self = .array(v)
  }

  /// Creates a new instance by decoding from the given decoder.
  ///
  /// This function throws an error if the data does not decode to any of the
  /// cases supported by `Value`.
  ///
  /// - Parameters:
  ///   - decoder: the decoder to read data from.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null(NullValue())
    } else if let v = try? container.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? container.decode(String.self) {
      // Try as a string first, because the decoder may treat some strings as numbers.
      self = .string(v)
    } else if let v = try? container.decode(Double.self) {
      self = .number(v)
    } else if let v = try? container.decode(Struct.self) {
      self = .object(v)
    } else if let v = try? container.decode(ListValue.self) {
      self = .array(v)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid Value")
    }
  }

  /// Encodes this value into the given encoder.
  ///
  /// This function throws an error if any values are invalid for the given
  /// encoder's format.
  ///
  /// - Parameters:
  ///   - encoder: The encoder to write data to.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .number(let v):
      try container.encode(v)
    case .string(let v):
      try container.encode(v)
    case .bool(let v):
      try container.encode(v)
    case .object(let v):
      try container.encode(v)
    case .array(let v):
      try container.encode(v)
    }
  }
}

// Makes `Value` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `Any`.
extension Value: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Value"
  }
  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[`Any`.valueField] else {
      throw AnyError.missingValueField
    }
    self = v
  }
  public func _pack() throws -> Struct {
    return [`Any`.valueField: self]
  }
}

/// Represents a JSON object.
///
/// An unordered key-value map, intending to perfectly capture the semantics of
/// a JSON object. This enables parsing any arbitrary JSON payload as a message
/// field in ProtoJSON format.
///
/// This follows RFC 8259 guidelines for interoperable JSON: notably this type
/// cannot represent large Int64 values or `NaN`/`Infinity` numbers,
/// since the JSON format generally does not support those values in its number
/// type.
public typealias Struct = [String: Value]

// Makes `Struct` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `Any`.
extension Struct: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Struct"
  }
  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard case let .object(v) = any.fields[`Any`.valueField] else {
      throw AnyError.invalidValueField
    }
    self = v
  }
  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(object: self)]
  }
}

/// Represents a JSON array.
public typealias ListValue = [Value]

// Makes `ListValue` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `Any`.
extension ListValue: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.ListValue"
  }
  public init(fromAny any: `Any`) throws {
    if Self._anyTypeUrl != any._type {
      throw AnyError.mismatchedTypeUrl
    }
    guard case let .array(v) = any.fields[`Any`.valueField] else {
      throw AnyError.invalidValueField
    }
    self = v
  }
  public func _pack() throws -> Struct {
    return [`Any`.valueField: Value(array: self)]
  }
}

/// Represents a JSON null.
public struct NullValue: Codable, Equatable, Sendable {
  /// Default initializer.
  public init() {}

  /// Creates a new instance by decoding from the given decoder.
  ///
  /// - Parameters:
  ///   - decoder: the decoder to read data from.
  ///
  ///- Throws: `DecodingError.dataCorruptedError` if the decoder contains a
  ///  non-null value.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a `null`")
  }

  /// Encodes this value into the given encoder.
  ///
  /// Throws an error if the encoder does not support `encodeNil()`.
  ///
  /// - Parameters:
  ///   - encoder: The encoder to write data to.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encodeNil()
  }
}
