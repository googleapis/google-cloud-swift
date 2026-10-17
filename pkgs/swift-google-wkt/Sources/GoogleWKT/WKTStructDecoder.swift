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

/// Decodes `Decodable` messages directly from a `WKTStruct` (`[String: WKTValue]`) in memory,
/// applying ProtoJSON rules without intermediate UTF-8 JSON serialization.
///
/// `WKTAny` stores packed messages in memory as a `WKTStruct` dictionary. Previously, unpacking a
/// message from `WKTAny` encoded `from.fields` to UTF-8 JSON `Data` via `_ProtoJSONEncoder` and
/// then decoded the target message from that `Data` via `_ProtoJSONDecoder`. `WKTStructDecoder`
/// eliminates that intermediate JSON round-trip by walking the in-memory `WKTValue` tree directly
/// while enforcing identical ProtoJSON decoding semantics:
/// - Numbers and booleans may be decoded from either `.number` / `.bool` or `.string` values
///   (including `"NaN"`, `"Infinity"`, and `"-Infinity"` for floating-point types).
/// - Integer decoding from `.number(Double)` uses `T(exactly:)` so non-integral or out-of-bounds
///   values fail with `DecodingError.dataCorrupted`.
/// - `Data` values are decoded from base64 strings.
/// - Missing keys in keyed containers fall back to `DecodeToDefault` so absent proto3 fields
///   initialize to their default zero/empty values.
struct WKTStructDecoder {
  init() {}

  func decode<T: Decodable>(_ type: T.Type, from fields: WKTStruct) throws -> T {
    // Fast path when the target type is already `WKTStruct` or `WKTValue`.
    if type == WKTStruct.self {
      return fields as! T
    }
    if type == WKTValue.self {
      return WKTValue.object(fields) as! T
    }
    let decoder = InternalValueDecoder(value: .object(fields), codingPath: [])
    return try T(from: decoder)
  }
}

/// A `Decoder` view over a single in-memory `WKTValue` node at a given `codingPath`.
fileprivate struct InternalValueDecoder: Decoder {
  let value: WKTValue
  let codingPath: [any CodingKey]

  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
  where Key: CodingKey {
    guard case .object(let dict) = self.value else {
      throw DecodingError.typeMismatch(
        [String: Any].self,
        DecodingError.Context(
          codingPath: self.codingPath,
          debugDescription: "Expected to decode Dictionary<String, Any>."
        )
      )
    }
    return KeyedDecodingContainer(
      InternalKeyedStructDecodingContainer<Key>(dict: dict, codingPath: self.codingPath)
    )
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array(let list) = self.value else {
      throw DecodingError.typeMismatch(
        [Any].self,
        DecodingError.Context(
          codingPath: self.codingPath,
          debugDescription: "Expected to decode Array<Any>."
        )
      )
    }
    return InternalUnkeyedStructDecodingContainer(list: list, codingPath: self.codingPath)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    return InternalSingleValueStructDecodingContainer(
      value: self.value, codingPath: self.codingPath)
  }
}

/// Single-value decoding container that implements ProtoJSON coercion rules (accepting both
/// native `.bool` / `.number` values and string-encoded representations) on a `WKTValue`.
fileprivate struct InternalSingleValueStructDecodingContainer: SingleValueDecodingContainer {
  let value: WKTValue
  let codingPath: [any CodingKey]

  func decodeNil() -> Bool {
    if case .null = self.value {
      return true
    }
    return false
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    if case .bool(let b) = self.value {
      return b
    }
    if case .string(let s) = self.value {
      if s == "true" {
        return true
      }
      if s == "false" {
        return false
      }
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type Bool.")
  }

  func decode(_ type: String.Type) throws -> String {
    if case .string(let s) = self.value {
      return s
    }
    throw DecodingError.typeMismatch(
      String.self,
      DecodingError.Context(
        codingPath: self.codingPath,
        debugDescription: "Expected to decode String."
      )
    )
  }

  func decode(_ type: Double.Type) throws -> Double {
    if case .number(let d) = self.value {
      return d
    }
    if case .string(let s) = self.value, let d = Double(s) {
      return d
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type Double.")
  }

  func decode(_ type: Float.Type) throws -> Float {
    if case .number(let d) = self.value {
      return Float(d)
    }
    if case .string(let s) = self.value, let f = Float(s) {
      return f
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type Float.")
  }

  func decode(_ type: Int.Type) throws -> Int { try decodeInteger(type) }
  func decode(_ type: UInt.Type) throws -> UInt { try decodeInteger(type) }
  func decode(_ type: Int8.Type) throws -> Int8 { try decodeInteger(type) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeInteger(type) }
  func decode(_ type: Int16.Type) throws -> Int16 { try decodeInteger(type) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeInteger(type) }
  func decode(_ type: Int32.Type) throws -> Int32 { try decodeInteger(type) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeInteger(type) }
  func decode(_ type: Int64.Type) throws -> Int64 { try decodeInteger(type) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeInteger(type) }
  func decode(_ type: Int128.Type) throws -> Int128 { try decodeInteger(type) }
  func decode(_ type: UInt128.Type) throws -> UInt128 { try decodeInteger(type) }

  private func decodeInteger<T: FixedWidthInteger & LosslessStringConvertible>(
    _ type: T.Type
  ) throws -> T {
    // ProtoJSON allows integers to be represented either as JSON numbers or as strings.
    // `T(exactly:)` rejects fractional `Double`s (e.g. `3.14`) and values outside `T.min...T.max`.
    if case .number(let d) = self.value, let exact = T(exactly: d) {
      return exact
    }
    if case .string(let s) = self.value, let parsed = T(s) {
      return parsed
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type \(type).")
  }

  private func decodeData() throws -> Data {
    let string = try self.decode(String.self)
    guard let data = Data(base64Encoded: string) else {
      throw DecodingError.dataCorruptedError(
        in: self, debugDescription: "Expected a base64 string.")
    }
    return data
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    // Intercept `Data`, WKT JSON types, and primitive types so they use ProtoJSON decoding
    // rules instead of `Foundation` / standard library `Decodable` defaults (which, for example,
    // expect `Data` to be a JSON array of bytes or reject string-encoded numbers).
    if type == Data.self { return try self.decodeData() as! T }
    if type == WKTValue.self { return self.value as! T }
    if type == WKTStruct.self, case .object(let dict) = self.value {
      return dict as! T
    }
    if type == WKTListValue.self, case .array(let list) = self.value {
      return list as! T
    }
    if type == Bool.self { return try self.decode(Bool.self) as! T }
    if type == String.self { return try self.decode(String.self) as! T }
    if type == Double.self { return try self.decode(Double.self) as! T }
    if type == Float.self { return try self.decode(Float.self) as! T }
    if type == Int.self { return try self.decode(Int.self) as! T }
    if type == UInt.self { return try self.decode(UInt.self) as! T }
    if type == Int8.self { return try self.decode(Int8.self) as! T }
    if type == UInt8.self { return try self.decode(UInt8.self) as! T }
    if type == Int16.self { return try self.decode(Int16.self) as! T }
    if type == UInt16.self { return try self.decode(UInt16.self) as! T }
    if type == Int32.self { return try self.decode(Int32.self) as! T }
    if type == UInt32.self { return try self.decode(UInt32.self) as! T }
    if type == Int64.self { return try self.decode(Int64.self) as! T }
    if type == UInt64.self { return try self.decode(UInt64.self) as! T }
    if type == Int128.self { return try self.decode(Int128.self) as! T }
    if type == UInt128.self { return try self.decode(UInt128.self) as! T }
    return try T(from: InternalValueDecoder(value: self.value, codingPath: self.codingPath))
  }
}

/// Keyed decoding container backed by a `WKTStruct` (`[String: WKTValue]`).
///
/// Missing keys fall back to `DecodeToDefault` when decoded via non-optional `decode(_:forKey:)`,
/// matching proto3 default-value semantics in `_ProtoJSONDecoder`.
fileprivate struct InternalKeyedStructDecodingContainer<K: CodingKey>:
  KeyedDecodingContainerProtocol
{
  typealias Key = K

  let dict: WKTStruct
  let codingPath: [any CodingKey]

  var allKeys: [K] {
    self.dict.keys.compactMap { K(stringValue: $0) }
  }

  func contains(_ key: K) -> Bool {
    self.dict[key.stringValue] != nil
  }

  func decodeNil(forKey key: K) throws -> Bool {
    guard let entry = self.dict[key.stringValue] else {
      return true
    }
    if case .null = entry {
      return true
    }
    return false
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {
    // In proto3, omitted fields on the wire decode to their default value (`0`, `""`, `false`,
    // `[]`, `[:]`, or a default-initialized nested message).
    guard let entry = self.dict[key.stringValue] else {
      let decoder = DecodeToDefault()
      return try T(from: decoder)
    }
    // Fast paths for `Data` (base64 string) and WKT JSON types (`WKTValue`, `WKTStruct`,
    // `WKTListValue`) to avoid re-walking the `WKTValue` subtree.
    if type == Data.self {
      return try self.decodeData(from: entry, forKey: key) as! T
    }
    if type == WKTValue.self {
      return entry as! T
    }
    if type == WKTStruct.self, case .object(let nestedDict) = entry {
      return nestedDict as! T
    }
    if type == WKTListValue.self, case .array(let nestedList) = entry {
      return nestedList as! T
    }
    let decoder = InternalValueDecoder(value: entry, codingPath: self.codingPath + [key])
    return try T(from: decoder)
  }

  private func decodeData(from entry: WKTValue, forKey key: K) throws -> Data {
    guard case .string(let string) = entry else {
      throw DecodingError.typeMismatch(
        String.self,
        DecodingError.Context(
          codingPath: self.codingPath + [key],
          debugDescription: "Expected to decode String."
        )
      )
    }
    guard let data = Data(base64Encoded: string) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "Expected a base64 encoded string")
    }
    return data
  }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws
    -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
  {
    guard let entry = self.dict[key.stringValue] else {
      return KeyedDecodingContainer(DecodeToDefaultKeyed<NestedKey>())
    }
    guard case .object(let nestedDict) = entry else {
      throw DecodingError.typeMismatch(
        [String: Any].self,
        DecodingError.Context(
          codingPath: self.codingPath + [key],
          debugDescription: "Expected to decode Dictionary<String, Any>."
        )
      )
    }
    return KeyedDecodingContainer(
      InternalKeyedStructDecodingContainer<NestedKey>(
        dict: nestedDict, codingPath: self.codingPath + [key])
    )
  }

  func nestedUnkeyedContainer(forKey key: K) throws -> any UnkeyedDecodingContainer {
    guard let entry = self.dict[key.stringValue] else {
      throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(
          codingPath: self.codingPath,
          debugDescription: "Unkeyed container not found for key \(key.stringValue)."
        )
      )
    }
    guard case .array(let list) = entry else {
      throw DecodingError.typeMismatch(
        [Any].self,
        DecodingError.Context(
          codingPath: self.codingPath + [key],
          debugDescription: "Expected to decode Array<Any>."
        )
      )
    }
    return InternalUnkeyedStructDecodingContainer(list: list, codingPath: self.codingPath + [key])
  }

  func superDecoder() throws -> any Decoder {
    let superKey = _DynamicCodingKey(stringValue: "super")
    guard let entry = self.dict[superKey.stringValue] else {
      return DecodeToDefault()
    }
    return InternalValueDecoder(value: entry, codingPath: self.codingPath + [superKey])
  }

  func superDecoder(forKey key: K) throws -> any Decoder {
    guard let entry = self.dict[key.stringValue] else {
      return DecodeToDefault()
    }
    return InternalValueDecoder(value: entry, codingPath: self.codingPath + [key])
  }
}

/// Unkeyed decoding container backed by a `WKTListValue` (`[WKTValue]`).
fileprivate struct InternalUnkeyedStructDecodingContainer: UnkeyedDecodingContainer {
  let list: WKTListValue
  let codingPath: [any CodingKey]
  var currentIndex: Int = 0

  var count: Int? { self.list.count }
  var isAtEnd: Bool { self.currentIndex >= self.list.count }

  mutating func decodeNil() throws -> Bool {
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        Any?.self,
        DecodingError.Context(
          codingPath: self.codingPath + [_DynamicCodingKey(intValue: self.currentIndex)!],
          debugDescription: "Unkeyed container is at end."
        )
      )
    }
    if case .null = self.list[self.currentIndex] {
      self.currentIndex += 1
      return true
    }
    return false
  }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let idxKey = _DynamicCodingKey(intValue: self.currentIndex)!
    let itemPath = self.codingPath + [idxKey]
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        type,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Unkeyed container is at end."
        )
      )
    }
    let entry = self.list[self.currentIndex]
    self.currentIndex += 1

    if type == Data.self {
      guard case .string(let string) = entry else {
        throw DecodingError.typeMismatch(
          String.self,
          DecodingError.Context(
            codingPath: itemPath,
            debugDescription: "Expected to decode String."
          )
        )
      }
      guard let data = Data(base64Encoded: string) else {
        throw DecodingError.dataCorruptedError(
          in: self, debugDescription: "Expected a base64 string.")
      }
      return data as! T
    }
    if type == WKTValue.self {
      return entry as! T
    }
    if type == WKTStruct.self, case .object(let nestedDict) = entry {
      return nestedDict as! T
    }
    if type == WKTListValue.self, case .array(let nestedList) = entry {
      return nestedList as! T
    }
    return try T(from: InternalValueDecoder(value: entry, codingPath: itemPath))
  }

  mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let idxKey = _DynamicCodingKey(intValue: self.currentIndex)!
    let itemPath = self.codingPath + [idxKey]
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        KeyedDecodingContainer<NestedKey>.self,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Unkeyed container is at end."
        )
      )
    }
    let entry = self.list[self.currentIndex]
    self.currentIndex += 1
    guard case .object(let nestedDict) = entry else {
      throw DecodingError.typeMismatch(
        [String: Any].self,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Expected to decode Dictionary<String, Any>."
        )
      )
    }
    return KeyedDecodingContainer(
      InternalKeyedStructDecodingContainer<NestedKey>(dict: nestedDict, codingPath: itemPath)
    )
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let idxKey = _DynamicCodingKey(intValue: self.currentIndex)!
    let itemPath = self.codingPath + [idxKey]
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        (any UnkeyedDecodingContainer).self,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Unkeyed container is at end."
        )
      )
    }
    let entry = self.list[self.currentIndex]
    self.currentIndex += 1
    guard case .array(let nestedList) = entry else {
      throw DecodingError.typeMismatch(
        [Any].self,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Expected to decode Array<Any>."
        )
      )
    }
    return InternalUnkeyedStructDecodingContainer(list: nestedList, codingPath: itemPath)
  }

  mutating func superDecoder() throws -> any Decoder {
    let idxKey = _DynamicCodingKey(intValue: self.currentIndex)!
    let itemPath = self.codingPath + [idxKey]
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        (any Decoder).self,
        DecodingError.Context(
          codingPath: itemPath,
          debugDescription: "Unkeyed container is at end."
        )
      )
    }
    let entry = self.list[self.currentIndex]
    self.currentIndex += 1
    return InternalValueDecoder(value: entry, codingPath: itemPath)
  }
}
