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
/// `WKTValue` represents a dynamically typed value which can be either
/// null, a number, a string, a boolean, a recursive struct value, or a
/// list of values. A producer of value is expected to set one of these
/// variants. Absence of any variant is an invalid state.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum WKTValue: Codable, Equatable, Sendable {
  /// Represents a JSON `null`.
  case null(WKTNullValue)

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
  case object(WKTStruct)

  /// Represents a JSON array.
  case array(WKTListValue)

  /// Initialize a value to the default: [`null`](doc:WKTValue/null(_:)).
  public init() {
    self = .null(WKTNullValue())
  }

  /// Initialize a value from a ``WKTNullValue``.
  public init(null v: WKTNullValue) {
    self = .null(WKTNullValue())
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
  public init(object v: WKTStruct) {
    self = .object(v)
  }

  /// Initialize a `WKTValue` with an array.
  public init(array v: WKTListValue) {
    self = .array(v)
  }

  /// Creates a new instance by decoding from the given decoder.
  ///
  /// This function throws an error if the data does not decode to any of the
  /// cases supported by `WKTValue`.
  ///
  /// - Parameters:
  ///   - decoder: the decoder to read data from.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null(WKTNullValue())
    } else if let v = try? container.decode(String.self) {
      // Try as a string first, because the decoder may treat some strings as numbers or booleans.
      self = .string(v)
    } else if let v = try? container.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? container.decode(Double.self), v.isFinite {
      self = .number(v)
    } else if let v = try? container.decode(WKTStruct.self) {
      self = .object(v)
    } else if let v = try? container.decode(WKTListValue.self) {
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
      guard v.isFinite else {
        throw EncodingError.invalidValue(
          v,
          EncodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "Value.number cannot be NaN or Infinity."
          )
        )
      }
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

// Makes `WKTValue` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTValue: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Value"
  }
  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard let v = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.missingValueField
    }
    self = v
  }
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: self]
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
public typealias WKTStruct = [String: WKTValue]

// Makes `WKTStruct` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTStruct: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.Struct"
  }
  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard case let .object(v) = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.invalidValueField
    }
    self = v
  }
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: WKTValue(object: self)]
  }
}

/// Represents a JSON array.
public typealias WKTListValue = [WKTValue]

// Makes `WKTListValue` conform to the `_AnyPackable` protocol, so we can pack and unpack them from `WKTAny`.
extension WKTListValue: _AnyPackable {
  public static var _anyTypeUrl: String {
    return "type.googleapis.com/google.protobuf.ListValue"
  }
  public init(fromAny any: WKTAny) throws {
    if Self._anyTypeUrl != any._type {
      throw WKTAnyError.mismatchedTypeUrl
    }
    guard case let .array(v) = any.fields[WKTAny.valueField] else {
      throw WKTAnyError.invalidValueField
    }
    self = v
  }
  public func _pack() throws -> WKTStruct {
    return [WKTAny.valueField: WKTValue(array: self)]
  }
}

/// Represents a JSON null.
public struct WKTNullValue: Codable, Equatable, Sendable {
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
