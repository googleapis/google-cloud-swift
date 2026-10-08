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

extension Row {
  /// Decodes the row into a `Decodable` type, matching properties to columns by name.
  ///
  /// ```swift
  /// struct Person: Decodable {
  ///   var name: String
  ///   var age: Int64?
  ///   var tags: [String]
  ///   var address: Address  // a STRUCT column
  /// }
  /// let person = try row.decode(Person.self)
  /// ```
  ///
  /// Names match exactly first, then case-insensitively. Each column converts as its typed
  /// accessor on ``FieldValue`` does, with these Swift types:
  ///
  /// | Swift type | Column type |
  /// | ---------- | ----------- |
  /// | `String` | any scalar, as text |
  /// | `Bool`, integers, `Double`, `Float` | `BOOL`, `INT64`, `FLOAT64` |
  /// | `Decimal`, ``BigNumeric`` | `NUMERIC`, `BIGNUMERIC` |
  /// | `Date` | `TIMESTAMP` |
  /// | `Data` | `BYTES` |
  /// | ``BigQueryDate``, ``BigQueryTime``, ``BigQueryDateTime`` | `DATE`, `TIME`, `DATETIME` |
  /// | ``Interval``, ``BigQueryRange`` | `INTERVAL`, `RANGE` (with its element type) |
  /// | arrays | `REPEATED` columns |
  /// | nested `Decodable` types, ``Row`` | `STRUCT` columns |
  /// | ``FieldValue`` | any column, unconverted |
  ///
  /// Optional properties decode `NULL` (or a missing column) as `nil`.
  ///
  /// - Throws: `DecodingError` if a column is missing, `NULL` for a non-optional property, or
  ///   not convertible to the property type.
  public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
    try RowDecoder.decode(T.self, value: .record(self), field: nil, codingPath: [])
  }
}

extension FieldValue: Decodable {
  /// Decodes the unconverted cell value of a property in ``Row/decode(_:)``.
  ///
  /// - Throws: `DecodingError.typeMismatch` with any decoder other than ``Row/decode(_:)``'s.
  public init(from decoder: any Decoder) throws {
    guard let decoder = decoder as? RowDecoder else {
      throw DecodingError.typeMismatch(
        FieldValue.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "FieldValue can only be decoded with Row.decode(_:)"))
    }
    self = decoder.value
  }
}

extension Row: Decodable {
  /// Decodes a `STRUCT` property in ``Row/decode(_:)`` without converting its values.
  ///
  /// - Throws: `DecodingError.typeMismatch` with any decoder other than ``Row/decode(_:)``'s,
  ///   or if the value is not a `STRUCT`.
  public init(from decoder: any Decoder) throws {
    guard let decoder = decoder as? RowDecoder, case .record(let row) = decoder.value else {
      throw DecodingError.typeMismatch(
        Row.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Row can only be decoded from a STRUCT with Row.decode(_:)"))
    }
    self = row
  }
}

/// A `Decoder` over one cell value and its schema field.
struct RowDecoder: Decoder {
  let value: FieldValue
  let field: Field?
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  /// Decodes `value`, handling the Foundation and BigQuery types whose own `Decodable`
  /// conformance does not match the BigQuery row format.
  static func decode<T: Decodable>(
    _ type: T.Type, value: FieldValue, field: Field?, codingPath: [any CodingKey]
  ) throws -> T {
    func required<V>(_ read: () throws -> V?) throws -> T {
      guard let result = try withPath(codingPath, read) else {
        throw DecodingError.valueNotFound(
          T.self,
          DecodingError.Context(codingPath: codingPath, debugDescription: "the value is NULL"))
      }
      return result as! T
    }
    switch type {
    case is FieldValue.Type: return value as! T
    case is Row.Type: return try required { try value.recordValue }
    case is Date.Type: return try required { try value.timestampValue }
    case is Data.Type: return try required { try value.bytesValue }
    case is Decimal.Type: return try required { try value.numericValue }
    case is BigQueryRange.Type:
      return try required {
        var range = try value.rangeValue
        range?.elementType = field?.rangeElementType
        return range
      }
    default:
      return try T(from: RowDecoder(value: value, field: field, codingPath: codingPath))
    }
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .record(let row) = self.value else {
      throw self.mismatch(Row.self)
    }
    return KeyedDecodingContainer(RowKeyedContainer<Key>(row: row, codingPath: self.codingPath))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array(let elements) = self.value else {
      throw self.mismatch([FieldValue].self)
    }
    var element = self.field
    element?.mode = .nullable
    return RowUnkeyedContainer(elements: elements, field: element, codingPath: self.codingPath)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    RowSingleValueContainer(decoder: self)
  }

  private func mismatch(_ type: Any.Type) -> DecodingError {
    let shape =
      switch self.value {
      case .null: "NULL"
      case .scalar: "a scalar"
      case .array: "an array"
      case .record: "a struct"
      }
    return DecodingError.typeMismatch(
      type,
      DecodingError.Context(codingPath: self.codingPath, debugDescription: "the value is \(shape)"))
  }
}

/// Runs `body`, adding `codingPath` to the context of any `DecodingError` it throws.
private func withPath<V>(_ codingPath: [any CodingKey], _ body: () throws -> V) throws -> V {
  do {
    return try body()
  } catch DecodingError.dataCorrupted(let context) {
    throw DecodingError.dataCorrupted(context.prefixed(codingPath))
  } catch DecodingError.typeMismatch(let type, let context) {
    throw DecodingError.typeMismatch(type, context.prefixed(codingPath))
  }
}

extension DecodingError.Context {
  fileprivate func prefixed(_ path: [any CodingKey]) -> DecodingError.Context {
    DecodingError.Context(
      codingPath: path + self.codingPath, debugDescription: self.debugDescription,
      underlyingError: self.underlyingError)
  }
}

/// A coding key for an array index.
private struct IndexKey: CodingKey {
  let intValue: Int?
  var stringValue: String { "Index \(self.intValue ?? 0)" }
  init(_ index: Int) { self.intValue = index }
  init?(stringValue: String) { nil }
  init?(intValue: Int) { self.intValue = intValue }
}

private struct RowSingleValueContainer: SingleValueDecodingContainer {
  let decoder: RowDecoder
  var codingPath: [any CodingKey] { self.decoder.codingPath }

  func decodeNil() -> Bool { self.decoder.value == .null }

  func decode(_ type: Bool.Type) throws -> Bool { try self.read { try $0.boolValue } }
  func decode(_ type: String.Type) throws -> String { try self.read { try $0.stringValue } }
  func decode(_ type: Double.Type) throws -> Double { try self.read { try $0.doubleValue } }
  func decode(_ type: Float.Type) throws -> Float { try self.number(Float.init) }
  func decode(_ type: Int.Type) throws -> Int { try self.integer() }
  func decode(_ type: Int8.Type) throws -> Int8 { try self.integer() }
  func decode(_ type: Int16.Type) throws -> Int16 { try self.integer() }
  func decode(_ type: Int32.Type) throws -> Int32 { try self.integer() }
  func decode(_ type: Int64.Type) throws -> Int64 { try self.integer() }
  func decode(_ type: UInt.Type) throws -> UInt { try self.integer() }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try self.integer() }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try self.integer() }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try self.integer() }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try self.integer() }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try RowDecoder.decode(
      T.self, value: self.decoder.value, field: self.decoder.field, codingPath: self.codingPath)
  }

  private func read<T>(_ accessor: (FieldValue) throws -> T?) throws -> T {
    guard let value = try withPath(self.codingPath, { try accessor(self.decoder.value) }) else {
      throw DecodingError.valueNotFound(
        T.self,
        DecodingError.Context(codingPath: self.codingPath, debugDescription: "the value is NULL"))
    }
    return value
  }

  private func number<T>(_ convert: (String) -> T?) throws -> T {
    let text = try self.read { try $0.stringValue }
    guard let value = convert(text) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: self.codingPath, debugDescription: "cannot read \"\(text)\" as \(T.self)"))
    }
    return value
  }

  private func integer<T: FixedWidthInteger>() throws -> T {
    try self.number { T($0) }
  }
}

private struct RowKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let row: Row
  let codingPath: [any CodingKey]

  var allKeys: [Key] { self.row.schema.fields.compactMap { Key(stringValue: $0.name) } }

  func contains(_ key: Key) -> Bool { self.row[key.stringValue] != nil }

  func decodeNil(forKey key: Key) throws -> Bool { try self.cell(key).value == .null }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try self.value(type, key) }
  func decode(_ type: String.Type, forKey key: Key) throws -> String { try self.value(type, key) }
  func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try self.value(type, key) }
  func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try self.value(type, key) }
  func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try self.value(type, key) }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try self.value(type, key) }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try self.value(type, key) }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try self.value(type, key) }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try self.value(type, key) }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try self.value(type, key) }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try self.value(type, key) }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try self.value(type, key) }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try self.value(type, key) }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try self.value(type, key) }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try self.value(type, key)
  }

  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type, forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try self.decoder(key).container(keyedBy: type)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try self.decoder(key).unkeyedContainer()
  }

  func superDecoder() throws -> any Decoder {
    RowDecoder(value: .record(self.row), field: nil, codingPath: self.codingPath)
  }

  func superDecoder(forKey key: Key) throws -> any Decoder {
    try self.decoder(key)
  }

  private func cell(_ key: Key) throws -> (value: FieldValue, field: Field) {
    guard let index = self.row.schema.index(of: key.stringValue), index < self.row.values.count
    else {
      throw DecodingError.keyNotFound(
        key,
        DecodingError.Context(
          codingPath: self.codingPath, debugDescription: "no column named \"\(key.stringValue)\""))
    }
    return (self.row.values[index], self.row.schema.fields[index])
  }

  private func decoder(_ key: Key) throws -> RowDecoder {
    let cell = try self.cell(key)
    return RowDecoder(value: cell.value, field: cell.field, codingPath: self.codingPath + [key])
  }

  private func value<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
    let cell = try self.cell(key)
    return try RowDecoder.decode(
      T.self, value: cell.value, field: cell.field, codingPath: self.codingPath + [key])
  }
}

private struct RowUnkeyedContainer: UnkeyedDecodingContainer {
  let elements: [FieldValue]
  let field: Field?
  let codingPath: [any CodingKey]
  private(set) var currentIndex = 0

  init(elements: [FieldValue], field: Field?, codingPath: [any CodingKey]) {
    self.elements = elements
    self.field = field
    self.codingPath = codingPath
  }

  var count: Int? { self.elements.count }
  var isAtEnd: Bool { self.currentIndex >= self.elements.count }

  mutating func decodeNil() throws -> Bool {
    guard !self.isAtEnd, self.elements[self.currentIndex] == .null else { return false }
    self.currentIndex += 1
    return true
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool { try self.next(type) }
  mutating func decode(_ type: String.Type) throws -> String { try self.next(type) }
  mutating func decode(_ type: Double.Type) throws -> Double { try self.next(type) }
  mutating func decode(_ type: Float.Type) throws -> Float { try self.next(type) }
  mutating func decode(_ type: Int.Type) throws -> Int { try self.next(type) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { try self.next(type) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { try self.next(type) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { try self.next(type) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { try self.next(type) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { try self.next(type) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try self.next(type) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try self.next(type) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try self.next(type) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try self.next(type) }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try self.next(type) }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    try self.nextDecoder().container(keyedBy: type)
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    try self.nextDecoder().unkeyedContainer()
  }

  mutating func superDecoder() throws -> any Decoder {
    try self.nextDecoder()
  }

  private mutating func nextDecoder() throws -> RowDecoder {
    let path = try self.nextPath(RowDecoder.self)
    defer { self.currentIndex += 1 }
    return RowDecoder(value: self.elements[self.currentIndex], field: self.field, codingPath: path)
  }

  private mutating func next<T: Decodable>(_ type: T.Type) throws -> T {
    let path = try self.nextPath(type)
    let value = try RowDecoder.decode(
      T.self, value: self.elements[self.currentIndex], field: self.field, codingPath: path)
    self.currentIndex += 1
    return value
  }

  private func nextPath(_ type: Any.Type) throws -> [any CodingKey] {
    let path = self.codingPath + [IndexKey(self.currentIndex)]
    guard !self.isAtEnd else {
      throw DecodingError.valueNotFound(
        type,
        DecodingError.Context(codingPath: path, debugDescription: "the array has no more elements"))
    }
    return path
  }
}
