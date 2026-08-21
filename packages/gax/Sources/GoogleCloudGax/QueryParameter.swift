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

/// Encodes a field as an array of query parameters.
///
/// The Google Cloud client libraries for Swift use HTTP+JSON as their primary transport. In this
/// transport, some request fields are represented as query parameters. The serialization of these
/// fields as query parameters is described in:
///     <https://github.com/googleapis/googleapis/blob/16b4737e7b870914e0c384b87f0e50ed388aa225/google/api/http.proto#L87-L118>
///
/// This type implements the rules for any encodable type, including well-known types.
@_spi(GoogleCloudInternal) public class _QueryParameterEncoder {
  public init() {}

  /// Encodes `value` as an array of query parameters with `prefix` as the base name.
  ///
  /// - Parameters:
  ///   - `value`: the value to encode.
  ///   - `prefix`: the prefix for all the names in the resulting array.
  ///
  /// - Returns: the field value serialized as follows:
  ///   - Primitive types (bool, strings, integers) return an array with a single `URLQueryItem`
  ///     where the name is `prefix` and the value is `value` as a string.
  ///   - Arrays return an array where every element has the same prefix.
  ///   - Structs return an array where every element is prefixed with `prefix.` and then the name
  ///     of each field in the struct.
  ///
  /// - Throws: an error if the value cannot be serialized, though this should be rare.
  public func encode<T: Encodable>(_ value: T, prefix: String) throws -> [URLQueryItem] {
    let encoder = InternalEncoder(prefix: prefix)
    try value.encode(to: encoder)
    return encoder.queryItems
  }
}

private struct StringKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

private class InternalEncoder: Encoder {
  var codingPath: [CodingKey]
  var userInfo: [CodingUserInfoKey: Any] = [:]
  var queryItems: [URLQueryItem] = []

  init(prefix: String) {
    self.codingPath = [StringKey(stringValue: prefix)]
  }

  func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
    return KeyedEncodingContainer(
      InternalKeyedContainer<Key>(encoder: self, codingPath: self.codingPath))
  }

  func unkeyedContainer() -> UnkeyedEncodingContainer {
    return InternalUnkeyedContainer(encoder: self, codingPath: self.codingPath)
  }

  func singleValueContainer() -> SingleValueEncodingContainer {
    return self
  }

  func append(_ value: String) {
    let name = codingPath.map { $0.stringValue }.joined(separator: ".")
    queryItems.append(URLQueryItem(name: name, value: value))
  }
}

extension InternalEncoder: SingleValueEncodingContainer {
  func encodeNil() throws {}

  func encode(_ value: Bool) throws { append(value ? "true" : "false") }
  func encode(_ value: String) throws { append(value) }
  func encode(_ value: Double) throws { append(String(value)) }
  func encode(_ value: Float) throws { append(String(value)) }
  func encode(_ value: Int) throws { append(String(value)) }
  func encode(_ value: Int8) throws { append(String(value)) }
  func encode(_ value: Int16) throws { append(String(value)) }
  func encode(_ value: Int32) throws { append(String(value)) }
  func encode(_ value: Int64) throws { append(String(value)) }
  func encode(_ value: UInt) throws { append(String(value)) }
  func encode(_ value: UInt8) throws { append(String(value)) }
  func encode(_ value: UInt16) throws { append(String(value)) }
  func encode(_ value: UInt32) throws { append(String(value)) }
  func encode(_ value: UInt64) throws { append(String(value)) }

  func encode<T>(_ value: T) throws where T: Encodable {
    if let data = value as? Data {
      append(data.base64EncodedString())
      return
    }
    try value.encode(to: self)
  }
}

private struct InternalKeyedContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
  typealias Key = K
  let encoder: InternalEncoder
  let codingPath: [CodingKey]

  init(encoder: InternalEncoder, codingPath: [CodingKey]) {
    self.encoder = encoder
    self.codingPath = codingPath
  }

  private func encodeGeneric<T: Encodable>(_ value: T, forKey key: Key) throws {
    let oldPath = encoder.codingPath
    encoder.codingPath = codingPath + [key]
    defer { encoder.codingPath = oldPath }
    if let data = value as? Data {
      encoder.append(data.base64EncodedString())
      return
    }
    try value.encode(to: encoder)
  }

  func encodeNil(forKey key: Key) throws {}
  func encode(_ value: Bool, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: String, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Double, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Float, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Int, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Int8, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Int16, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Int32, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: Int64, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: UInt, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: UInt8, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: UInt16, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: UInt32, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode(_ value: UInt64, forKey key: Key) throws { try encodeGeneric(value, forKey: key) }
  func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    try encodeGeneric(value, forKey: key)
  }

  func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    return KeyedEncodingContainer(
      InternalKeyedContainer<NestedKey>(encoder: encoder, codingPath: codingPath + [key]))
  }

  func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
    return InternalUnkeyedContainer(encoder: encoder, codingPath: codingPath + [key])
  }

  func superEncoder() -> Encoder {
    encoder.codingPath = codingPath
    return encoder
  }
  func superEncoder(forKey key: Key) -> Encoder {
    encoder.codingPath = codingPath + [key]
    return encoder
  }
}

private struct InternalUnkeyedContainer: UnkeyedEncodingContainer {
  let encoder: InternalEncoder
  let codingPath: [CodingKey]
  private(set) var count: Int = 0

  init(encoder: InternalEncoder, codingPath: [CodingKey]) {
    self.encoder = encoder
    self.codingPath = codingPath
  }

  private mutating func encodeGeneric<T: Encodable>(_ value: T) throws {
    let oldPath = encoder.codingPath
    encoder.codingPath = codingPath
    defer {
      encoder.codingPath = oldPath
    }
    if let data = value as? Data {
      encoder.append(data.base64EncodedString())
      return
    }
    try value.encode(to: encoder)
  }

  mutating func encodeNil() throws {
  }
  mutating func encode(_ value: Bool) throws { try encodeGeneric(value) }
  mutating func encode(_ value: String) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Double) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Float) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Int) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Int8) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Int16) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Int32) throws { try encodeGeneric(value) }
  mutating func encode(_ value: Int64) throws { try encodeGeneric(value) }
  mutating func encode(_ value: UInt) throws { try encodeGeneric(value) }
  mutating func encode(_ value: UInt8) throws { try encodeGeneric(value) }
  mutating func encode(_ value: UInt16) throws { try encodeGeneric(value) }
  mutating func encode(_ value: UInt32) throws { try encodeGeneric(value) }
  mutating func encode(_ value: UInt64) throws { try encodeGeneric(value) }
  mutating func encode<T: Encodable>(_ value: T) throws { try encodeGeneric(value) }

  mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let container = KeyedEncodingContainer(
      InternalKeyedContainer<NestedKey>(encoder: encoder, codingPath: codingPath))
    return container
  }

  mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
    let container = InternalUnkeyedContainer(encoder: encoder, codingPath: codingPath)
    return container
  }

  mutating func superEncoder() -> Encoder {
    encoder.codingPath = codingPath
    return encoder
  }
}
