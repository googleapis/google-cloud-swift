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

/// Decodes types to their default values.
///
/// When ``ProtoJSONDecoder`` finds a missing key it creates an instance of this decoder to
/// initialize the element to its default.
struct DecodeToDefault {
  func decodeGeneric(_ type: Data.Type) throws -> Data {
    return Data()
  }
  func decodeGeneric<T: Decodable>(_ type: T.Type) throws -> T {
    throw ProtoJSONError.unsupportedType("\(type)")
  }
}

extension DecodeToDefault: Decoder {
  var userInfo: [CodingUserInfoKey: Any] { [:] }
  var codingPath: [any CodingKey] { [] }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
  where Key: CodingKey {
    return KeyedDecodingContainer(DecodeToDefaultKeyed<Key>())
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    return Self()
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    return Self()
  }
}

struct DecodeToDefaultKeyed<K: CodingKey> {}
extension DecodeToDefaultKeyed: KeyedDecodingContainerProtocol {
  typealias Key = K
  var codingPath: [any CodingKey] { [] }
  var allKeys: [K] { [] }

  func contains(_ key: K) -> Bool { return true }

  func decodeNil(forKey key: K) throws -> Bool { return true }
  func decode(_: Bool.Type, forKey key: K) throws -> Bool { return Bool() }
  func decode(_: String.Type, forKey key: K) throws -> String { return String() }
  func decode(_: Int.Type, forKey key: K) throws -> Int { return Int() }
  func decode(_: UInt.Type, forKey key: K) throws -> UInt { return UInt() }
  func decode(_: Int8.Type, forKey key: K) throws -> Int8 { return Int8() }
  func decode(_: UInt8.Type, forKey key: K) throws -> UInt8 { return UInt8() }
  func decode(_: Int16.Type, forKey key: K) throws -> Int16 { return Int16() }
  func decode(_: UInt16.Type, forKey key: K) throws -> UInt16 { return UInt16() }
  func decode(_: Int32.Type, forKey key: K) throws -> Int32 { return Int32() }
  func decode(_: UInt32.Type, forKey key: K) throws -> UInt32 { return UInt32() }
  func decode(_: Int64.Type, forKey key: K) throws -> Int64 { return Int64() }
  func decode(_: UInt64.Type, forKey key: K) throws -> UInt64 { return UInt64() }
  func decode(_: Float.Type, forKey key: K) throws -> Float { return Float() }
  func decode(_: Double.Type, forKey key: K) throws -> Double { return Double() }

  func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {
    return try T(from: DecodeToDefault())
  }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws
    -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
  {
    return KeyedDecodingContainer(DecodeToDefaultKeyed<NestedKey>())
  }
  func nestedUnkeyedContainer(forKey key: K) throws -> any UnkeyedDecodingContainer {
    return DecodeToDefault()
  }
  func superDecoder() throws -> any Decoder { return DecodeToDefault() }
  func superDecoder(forKey key: K) throws -> any Decoder { return DecodeToDefault() }
}

/// Decode singular fields to their default value.
extension DecodeToDefault: SingleValueDecodingContainer {
  // This is the only interesting case, forward to decodeGeneric() to resolve `Data` vs. other types.
  func decode<T: Decodable>(_ type: T.Type) throws -> T { return try decodeGeneric(type) }

  func decodeNil() -> Bool { return true }
  func decode(_ type: Bool.Type) throws -> Bool { return Bool() }
  func decode(_ type: String.Type) throws -> String { return String() }
  func decode(_ type: Int.Type) throws -> Int { return Int() }
  func decode(_ type: UInt.Type) throws -> UInt { return UInt() }
  func decode(_ type: Int8.Type) throws -> Int8 { return Int8() }
  func decode(_ type: UInt8.Type) throws -> UInt8 { return UInt8() }
  func decode(_ type: Int16.Type) throws -> Int16 { return Int16() }
  func decode(_ type: UInt16.Type) throws -> UInt16 { return UInt16() }
  func decode(_ type: Int32.Type) throws -> Int32 { return Int32() }
  func decode(_ type: UInt32.Type) throws -> UInt32 { return UInt32() }
  func decode(_ type: Int64.Type) throws -> Int64 { return Int64() }
  func decode(_ type: UInt64.Type) throws -> UInt64 { return UInt64() }
  func decode(_ type: Int128.Type) throws -> Int128 { return Int128() }
  func decode(_ type: UInt128.Type) throws -> UInt128 { return UInt128() }
  func decode(_ type: Float.Type) throws -> Float { return Float() }
  func decode(_ type: Double.Type) throws -> Double { return Double() }
}

/// Decode repeated fields to their default value, that is, an empty array.
extension DecodeToDefault: UnkeyedDecodingContainer {
  var isAtEnd: Bool { true }
  var count: Int? { 0 }
  var currentIndex: Int { 0 }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey>
  where NestedKey: CodingKey {
    return KeyedDecodingContainer(DecodeToDefaultKeyed<NestedKey>())
  }

  func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    return Self()
  }
  func superDecoder() throws -> any Decoder {
    return Self()
  }
}
