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

/// Encodes values using the ProtoJSON mapping.
///
/// The Google Cloud client libraries for Swift use HTTP+JSON as their primary transport.
/// The ProtoJSON encoding differs from typical JSON in a number of ways, including:
/// - Non-number floating point values (NaN, +Inf, -Inf) are represented as strings.
/// - 64-bit integers (Int64, UInt64) are represented as strings.
///
/// This encoder configures the native Swift JSON encoder to implement ProtoJSON rules.
@_spi(GoogleCloudInternal) final public class _ProtoJSONEncoder {
  public var outputFormatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]

  public init() {}

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    let encoder = JSONEncoder()
    encoder.outputFormatting = self.outputFormatting
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    return try encoder.encode(Interceptor(inner: value))
  }
}

fileprivate protocol _OptionalProtocol {
  var _isNil: Bool { get }
  var _unwrappedValue: Any? { get }
}

extension Optional: _OptionalProtocol {
  var _isNil: Bool { self == nil }
  var _unwrappedValue: Any? {
    switch self {
    case .some(let val): return val
    case .none: return nil
    }
  }
}

fileprivate struct Interceptor<T: Encodable>: Encodable {
  let inner: T

  func encode(to encoder: any Encoder) throws {
    try self.inner.encode(to: InternalEncoder(impl: encoder))
  }
}

fileprivate struct InternalEncoder {
  let impl: any Encoder

  init(impl: any Encoder) { self.impl = impl }
}

extension InternalEncoder: Encoder {
  var codingPath: [any CodingKey] { self.impl.codingPath }
  var userInfo: [CodingUserInfoKey: Any] { self.impl.userInfo }

  func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
    let impl = self.impl.container(keyedBy: type)
    return KeyedEncodingContainer(InternalKeyedContainer(impl))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    let impl = self.impl.unkeyedContainer()
    return InternalUnkeyedEncodingContainer(impl)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    let impl = self.impl.singleValueContainer()
    return InternalSingleValueEncodingContainer(impl)
  }
}

fileprivate struct InternalKeyedContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
  typealias Key = K
  var impl: KeyedEncodingContainer<K>

  init(_ impl: KeyedEncodingContainer<K>) { self.impl = impl }

  var codingPath: [any CodingKey] { self.impl.codingPath }

  mutating func encodeNil(forKey key: K) throws {
    try self.impl.encodeNil(forKey: key)
  }

  mutating func encode(_ value: Bool, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: String, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Double, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Float, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int8, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int16, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int32, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int64, forKey key: K) throws {
    try self.impl.encode(String(value), forKey: key)
  }

  mutating func encode(_ value: UInt, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt8, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt16, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt32, forKey key: K) throws {
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt64, forKey key: K) throws {
    try self.impl.encode(String(value), forKey: key)
  }

  mutating func encode<T>(_ value: T, forKey key: K) throws where T: Encodable {
    if let opt = value as? _OptionalProtocol, opt._isNil {
      try self.impl.encodeNil(forKey: key)
    } else if let opt = value as? _OptionalProtocol, let unwrapped = opt._unwrappedValue {
      if let v = unwrapped as? Int64 {
        try self.impl.encode(String(v), forKey: key)
      } else if let v = unwrapped as? UInt64 {
        try self.impl.encode(String(v), forKey: key)
      } else {
        try self.impl.encode(Interceptor(inner: value), forKey: key)
      }
    } else if let v = value as? Int64 {
      try self.impl.encode(String(v), forKey: key)
    } else if let v = value as? UInt64 {
      try self.impl.encode(String(v), forKey: key)
    } else if let v = value as? String {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Bool {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Double {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Float {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Int {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Int8 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Int16 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Int32 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? UInt {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? UInt8 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? UInt16 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? UInt32 {
      try self.impl.encode(v, forKey: key)
    } else if let v = value as? Data {
      try self.impl.encode(v, forKey: key)
    } else {
      try self.impl.encode(Interceptor(inner: value), forKey: key)
    }
  }

  mutating func encodeConditional<T>(_ object: T, forKey key: K) throws
  where T: AnyObject, T: Encodable {
    try self.impl.encodeConditional(object, forKey: key)
  }

  mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let nested = self.impl.nestedContainer(keyedBy: keyType, forKey: key)
    return KeyedEncodingContainer(InternalKeyedContainer<NestedKey>(nested))
  }

  mutating func nestedUnkeyedContainer(forKey key: K) -> any UnkeyedEncodingContainer {
    let nested = self.impl.nestedUnkeyedContainer(forKey: key)
    return InternalUnkeyedEncodingContainer(nested)
  }

  mutating func superEncoder() -> any Encoder {
    return InternalEncoder(impl: self.impl.superEncoder())
  }

  mutating func superEncoder(forKey key: K) -> any Encoder {
    return InternalEncoder(impl: self.impl.superEncoder(forKey: key))
  }
}

fileprivate struct InternalUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  var impl: any UnkeyedEncodingContainer

  init(_ impl: any UnkeyedEncodingContainer) { self.impl = impl }

  var codingPath: [any CodingKey] { self.impl.codingPath }
  var count: Int { self.impl.count }

  mutating func encodeNil() throws {
    try self.impl.encodeNil()
  }

  mutating func encode(_ value: Bool) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: String) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Double) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Float) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int8) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int16) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int32) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int64) throws {
    try self.impl.encode(String(value))
  }

  mutating func encode(_ value: UInt) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt8) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt16) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt32) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt64) throws {
    try self.impl.encode(String(value))
  }

  mutating func encode<T>(_ value: T) throws where T: Encodable {
    if let opt = value as? _OptionalProtocol, opt._isNil {
      try self.impl.encodeNil()
    } else if let opt = value as? _OptionalProtocol, let unwrapped = opt._unwrappedValue {
      if let v = unwrapped as? Int64 {
        try self.impl.encode(String(v))
      } else if let v = unwrapped as? UInt64 {
        try self.impl.encode(String(v))
      } else {
        try self.impl.encode(Interceptor(inner: value))
      }
    } else if let v = value as? Int64 {
      try self.impl.encode(String(v))
    } else if let v = value as? UInt64 {
      try self.impl.encode(String(v))
    } else if let v = value as? String {
      try self.impl.encode(v)
    } else if let v = value as? Bool {
      try self.impl.encode(v)
    } else if let v = value as? Double {
      try self.impl.encode(v)
    } else if let v = value as? Float {
      try self.impl.encode(v)
    } else if let v = value as? Int {
      try self.impl.encode(v)
    } else if let v = value as? Int8 {
      try self.impl.encode(v)
    } else if let v = value as? Int16 {
      try self.impl.encode(v)
    } else if let v = value as? Int32 {
      try self.impl.encode(v)
    } else if let v = value as? UInt {
      try self.impl.encode(v)
    } else if let v = value as? UInt8 {
      try self.impl.encode(v)
    } else if let v = value as? UInt16 {
      try self.impl.encode(v)
    } else if let v = value as? UInt32 {
      try self.impl.encode(v)
    } else if let v = value as? Data {
      try self.impl.encode(v)
    } else {
      try self.impl.encode(Interceptor(inner: value))
    }
  }

  mutating func encodeConditional<T>(_ object: T) throws
  where T: AnyObject, T: Encodable {
    try self.impl.encodeConditional(object)
  }

  mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let nested = self.impl.nestedContainer(keyedBy: keyType)
    return KeyedEncodingContainer(InternalKeyedContainer<NestedKey>(nested))
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let nested = self.impl.nestedUnkeyedContainer()
    return InternalUnkeyedEncodingContainer(nested)
  }

  mutating func superEncoder() -> any Encoder {
    return InternalEncoder(impl: self.impl.superEncoder())
  }
}

fileprivate struct InternalSingleValueEncodingContainer: SingleValueEncodingContainer {
  var impl: any SingleValueEncodingContainer

  init(_ impl: any SingleValueEncodingContainer) { self.impl = impl }

  var codingPath: [any CodingKey] { self.impl.codingPath }

  mutating func encodeNil() throws {
    try self.impl.encodeNil()
  }

  mutating func encode(_ value: Bool) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: String) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Double) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Float) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int8) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int16) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int32) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: Int64) throws {
    try self.impl.encode(String(value))
  }

  mutating func encode(_ value: UInt) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt8) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt16) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt32) throws {
    try self.impl.encode(value)
  }

  mutating func encode(_ value: UInt64) throws {
    try self.impl.encode(String(value))
  }

  mutating func encode<T>(_ value: T) throws where T: Encodable {
    if let opt = value as? _OptionalProtocol, opt._isNil {
      try self.impl.encodeNil()
    } else if let opt = value as? _OptionalProtocol, let unwrapped = opt._unwrappedValue {
      if let v = unwrapped as? Int64 {
        try self.impl.encode(String(v))
      } else if let v = unwrapped as? UInt64 {
        try self.impl.encode(String(v))
      } else {
        try self.impl.encode(Interceptor(inner: value))
      }
    } else if let v = value as? Int64 {
      try self.impl.encode(String(v))
    } else if let v = value as? UInt64 {
      try self.impl.encode(String(v))
    } else if let v = value as? String {
      try self.impl.encode(v)
    } else if let v = value as? Bool {
      try self.impl.encode(v)
    } else if let v = value as? Double {
      try self.impl.encode(v)
    } else if let v = value as? Float {
      try self.impl.encode(v)
    } else if let v = value as? Int {
      try self.impl.encode(v)
    } else if let v = value as? Int8 {
      try self.impl.encode(v)
    } else if let v = value as? Int16 {
      try self.impl.encode(v)
    } else if let v = value as? Int32 {
      try self.impl.encode(v)
    } else if let v = value as? UInt {
      try self.impl.encode(v)
    } else if let v = value as? UInt8 {
      try self.impl.encode(v)
    } else if let v = value as? UInt16 {
      try self.impl.encode(v)
    } else if let v = value as? UInt32 {
      try self.impl.encode(v)
    } else if let v = value as? Data {
      try self.impl.encode(v)
    } else {
      try self.impl.encode(Interceptor(inner: value))
    }
  }
}
