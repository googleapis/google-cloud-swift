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
import GoogleWKT

/// The JSON forms of insertAll values (design §4.7).
enum InsertJSON {
  /// A number when exactly representable as a `Double` (|v| ≤ 2^53), otherwise a string.
  static func integer(_ value: some BinaryInteger) -> WKTValue {
    value.magnitude <= 1 << 53 ? .number(Double(value)) : .string(String(value))
  }

  /// A number, or `"NaN"`, `"Infinity"`, `"-Infinity"`.
  static func double(_ value: Double) -> WKTValue {
    if value.isNaN { return .string("NaN") }
    if value.isInfinite { return .string(value < 0 ? "-Infinity" : "Infinity") }
    return .number(value)
  }

  /// Like ``double(_:)``, keeping the `Float`'s shortest decimal form (`1.2`, not
  /// `1.2000000476837158`).
  static func float(_ value: Float) -> WKTValue {
    value.isFinite ? .number(Double(String(value)) ?? Double(value)) : self.double(Double(value))
  }

  /// An object with the bounds that are set: `{"start": "2024-01-01"}` for
  /// `[2024-01-01, UNBOUNDED)`. insertAll does not accept the `[start, end)` string form.
  static func range(_ value: BigQueryRange) -> WKTValue {
    var object: WKTStruct = [:]
    if let start = value.start { object["start"] = .string(start) }
    if let end = value.end { object["end"] = .string(end) }
    return .object(object)
  }

  /// An RFC 3339 UTC timestamp with microseconds, for example `2024-01-02T03:04:05.123456Z`.
  static func timestamp(_ value: Date) -> String {
    Timestamp.format(micros: Timestamp.micros(from: value), separator: "T", suffix: "Z")
  }
}

/// Encodes an `Encodable` value to JSON following the insertAll rules (design §4.7).
///
/// `JSONEncoder` is not used, because its `Date`, `Data`, and large-integer encodings do not match
/// what BigQuery expects.
enum InsertRowEncoder {
  /// The JSON form of `value`. A value that encodes nothing gives `null`.
  static func encode<T: Encodable>(_ value: T) throws -> WKTValue {
    let node = Node()
    try self.encode(value, into: node, codingPath: [])
    return node.resolved() ?? .null(WKTNullValue())
  }

  fileprivate static func encode<T: Encodable>(
    _ value: T, into node: Node, codingPath: [any CodingKey]
  ) throws {
    switch value {
    case let date as Date: node.value = .string(InsertJSON.timestamp(date))
    case let data as Data: node.value = .string(data.base64EncodedString())
    case let decimal as Decimal: node.value = .string(decimal.description)
    case let url as URL: node.value = .string(url.absoluteString)
    case let range as BigQueryRange: node.value = InsertJSON.range(range)
    default: try value.encode(to: NodeEncoder(node: node, codingPath: codingPath))
    }
  }
}

/// A JSON value under construction. Containers keep references to their children, so nested
/// containers can be filled in any order.
private final class Node {
  var value: WKTValue?
  var object: [String: Node]?
  var array: [Node]?

  /// The JSON value, or `nil` if nothing was encoded. Object members that encoded nothing or
  /// `null` are omitted; array elements that encoded nothing are `null`.
  func resolved() -> WKTValue? {
    if let object = self.object {
      return .object(
        object.compactMapValues { member in
          let value = member.resolved()
          if case .null? = value { return nil }
          return value
        })
    }
    if let array = self.array {
      return .array(array.map { $0.resolved() ?? .null(WKTNullValue()) })
    }
    return self.value
  }

  func child(_ key: String) -> Node {
    let child = Node()
    if self.object == nil { self.object = [:] }
    self.object?[key] = child
    return child
  }

  func appendChild() -> Node {
    let child = Node()
    if self.array == nil { self.array = [] }
    self.array?.append(child)
    return child
  }
}

private struct NodeEncoder: Encoder {
  let node: Node
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if self.node.object == nil { self.node.object = [:] }
    return KeyedEncodingContainer(KeyedContainer(node: self.node, codingPath: self.codingPath))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if self.node.array == nil { self.node.array = [] }
    return UnkeyedContainer(node: self.node, codingPath: self.codingPath)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    SingleValueContainer(node: self.node, codingPath: self.codingPath)
  }
}

private struct IndexKey: CodingKey {
  var stringValue: String { "Index \(self.intValue ?? 0)" }
  var intValue: Int?
  init(_ index: Int) { self.intValue = index }
  init?(stringValue: String) { nil }
  init?(intValue: Int) { self.intValue = intValue }
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let node: Node
  let codingPath: [any CodingKey]

  private func put<T: Encodable>(_ value: T, _ key: Key) throws {
    try InsertRowEncoder.encode(
      value, into: self.node.child(key.stringValue), codingPath: self.codingPath + [key])
  }

  // `nil` values are omitted.
  mutating func encodeNil(forKey key: Key) throws {}
  mutating func encode(_ value: Bool, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: String, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Double, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Float, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Int, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Int8, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Int16, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Int32, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: Int64, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: UInt, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: UInt8, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: UInt16, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: UInt32, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode(_ value: UInt64, forKey key: Key) throws { try self.put(value, key) }
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    try self.put(value, key)
  }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type, forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    NodeEncoder(node: self.node.child(key.stringValue), codingPath: self.codingPath + [key])
      .container(keyedBy: keyType)
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    NodeEncoder(node: self.node.child(key.stringValue), codingPath: self.codingPath + [key])
      .unkeyedContainer()
  }

  mutating func superEncoder() -> any Encoder {
    NodeEncoder(node: self.node.child("super"), codingPath: self.codingPath)
  }

  mutating func superEncoder(forKey key: Key) -> any Encoder {
    NodeEncoder(node: self.node.child(key.stringValue), codingPath: self.codingPath + [key])
  }
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
  let node: Node
  let codingPath: [any CodingKey]
  var count: Int { self.node.array?.count ?? 0 }

  private func nextPath() -> [any CodingKey] { self.codingPath + [IndexKey(self.count)] }

  private func put<T: Encodable>(_ value: T) throws {
    let path = self.nextPath()
    try InsertRowEncoder.encode(value, into: self.node.appendChild(), codingPath: path)
  }

  mutating func encodeNil() throws { self.node.appendChild().value = .null(WKTNullValue()) }
  mutating func encode(_ value: Bool) throws { try self.put(value) }
  mutating func encode(_ value: String) throws { try self.put(value) }
  mutating func encode(_ value: Double) throws { try self.put(value) }
  mutating func encode(_ value: Float) throws { try self.put(value) }
  mutating func encode(_ value: Int) throws { try self.put(value) }
  mutating func encode(_ value: Int8) throws { try self.put(value) }
  mutating func encode(_ value: Int16) throws { try self.put(value) }
  mutating func encode(_ value: Int32) throws { try self.put(value) }
  mutating func encode(_ value: Int64) throws { try self.put(value) }
  mutating func encode(_ value: UInt) throws { try self.put(value) }
  mutating func encode(_ value: UInt8) throws { try self.put(value) }
  mutating func encode(_ value: UInt16) throws { try self.put(value) }
  mutating func encode(_ value: UInt32) throws { try self.put(value) }
  mutating func encode(_ value: UInt64) throws { try self.put(value) }
  mutating func encode<T: Encodable>(_ value: T) throws { try self.put(value) }

  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy keyType: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    let path = self.nextPath()
    return NodeEncoder(node: self.node.appendChild(), codingPath: path).container(keyedBy: keyType)
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let path = self.nextPath()
    return NodeEncoder(node: self.node.appendChild(), codingPath: path).unkeyedContainer()
  }

  mutating func superEncoder() -> any Encoder {
    let path = self.nextPath()
    return NodeEncoder(node: self.node.appendChild(), codingPath: path)
  }
}

private struct SingleValueContainer: SingleValueEncodingContainer {
  let node: Node
  let codingPath: [any CodingKey]

  mutating func encodeNil() throws { self.node.value = .null(WKTNullValue()) }
  mutating func encode(_ value: Bool) throws { self.node.value = .bool(value) }
  mutating func encode(_ value: String) throws { self.node.value = .string(value) }
  mutating func encode(_ value: Double) throws { self.node.value = InsertJSON.double(value) }
  mutating func encode(_ value: Float) throws { self.node.value = InsertJSON.float(value) }
  mutating func encode(_ value: Int) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: Int8) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: Int16) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: Int32) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: Int64) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: UInt) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: UInt8) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: UInt16) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: UInt32) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode(_ value: UInt64) throws { self.node.value = InsertJSON.integer(value) }
  mutating func encode<T: Encodable>(_ value: T) throws {
    try InsertRowEncoder.encode(value, into: self.node, codingPath: self.codingPath)
  }
}
