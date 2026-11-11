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

public import Foundation

/// Decodes values using the ProtoJSON mapping.
///
/// The Google Cloud client libraries for Swift use HTTP+JSON as their primary transport.
/// The ProtoJSON encoding differs from typical JSON in a number of ways, including:
/// - Fields with a default value may be not present, that includes empty strings, empty repeated fields, and empty dictionaries.
/// - In principle, integer types with 0 value may be omitted too.
/// - Non-number floating point values (NaN, +Inf, -Inf) are represented as strings.
/// - Many numeric types can be represented as strings as well as numbers.
/// - Maps with numeric or boolean keys are serialized as string keys.
///
/// This decoder implements all the custom ProtoJSON rules using the native Swift JSON decoder.
/// The key idea is to wrap the JSON decoder types in our own types to handle missing values and alternative representations.
///
/// Unfortunately the system types conforming to the `Decoder` protocol are not public, they cannot be named to implement
/// any wrapper types. The approach is to use an `Interceptor<T>` type that implements `Decodable` and wraps the `any Decoder`
/// it receives.
@_spi(GoogleCloudInternal) final public class _ProtoJSONDecoder {
  public init() {}

  public func decode<T>(_ type: T.Type, from: Data) throws -> T where T: Decodable {
    let decoder = JSONDecoder()
    let proto = try decoder.decode(Interceptor<T>.self, from: from)
    return proto.inner
  }
}

/// Intercepts the decoding of `T` inserting the `Internal*` wrappers.
fileprivate struct Interceptor<T: Decodable>: Decodable {
  let inner: T

  init(from: any Decoder) throws {
    let decoder = InternalDecoder(impl: from, isMap: T.self is any _ProtoJSONMapMarker.Type)
    if T.self == Data.self {
      let container = try decoder.singleValueContainer()
      self.inner = try container.decode(Data.self) as! T
    } else {
      self.inner = try T(from: decoder)
    }
  }
}

/// Implements the `Decoder` protocol for ProtoJSON.
///
/// This wraps an implementation of the `Decoder` protocol and then applies the ProtoJSON rules.
fileprivate struct InternalDecoder {
  let impl: any Decoder
  let isMap: Bool

  init(impl: any Decoder, isMap: Bool = false) {
    self.impl = impl
    self.isMap = isMap
  }
}

// Implements the `Decoder` protocol.
extension InternalDecoder: Decoder {
  var codingPath: [any CodingKey] { self.impl.codingPath }
  var userInfo: [CodingUserInfoKey: Any] { self.impl.userInfo }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
  where Key: CodingKey {
    let impl = try self.impl.container(keyedBy: type)
    return KeyedDecodingContainer(InternalKeyedContainer(impl, isMap: self.isMap))
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    return InternalSingleValueContainer(try self.impl.singleValueContainer())
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let impl = try self.impl.unkeyedContainer()
    return InternalUnkeyedDecodingContainer(impl)
  }
}

fileprivate struct InternalSingleValueContainer {
  let impl: any SingleValueDecodingContainer
  init(_ impl: any SingleValueDecodingContainer) { self.impl = impl }

  func decodeGeneric<T: LosslessStringConvertible & Decodable>(_ type: T.Type) throws -> T {
    if let value = try? impl.decode(type) {
      return value
    }
    if let string = try? impl.decode(String.self), let value = T(string) {
      return value
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type \(type).")
  }

  func decodeData() throws -> Data {
    let string = try self.decode(String.self)
    guard let data = decodeProtoBase64(string) else {
      throw DecodingError.dataCorruptedError(
        in: self, debugDescription: "Expected a base64 string.")
    }
    return data
  }
}

extension InternalSingleValueContainer: SingleValueDecodingContainer {
  var codingPath: [any CodingKey] { impl.codingPath }

  func decodeNil() -> Bool { impl.decodeNil() }

  func decode(_ type: Bool.Type) throws -> Bool {
    if let value = try? impl.decode(type) {
      return value
    }
    if let value = try? impl.decode(String.self) {
      if value == "true" {
        return true
      }
      if value == "false" {
        return false
      }
    }
    throw DecodingError.dataCorruptedError(
      in: self, debugDescription: "Expected value of type Bool.")
  }
  func decode(_ type: Int.Type) throws -> Int { try decodeGeneric(type) }
  func decode(_ type: UInt.Type) throws -> UInt { try decodeGeneric(type) }
  func decode(_ type: Int8.Type) throws -> Int8 { try decodeGeneric(type) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeGeneric(type) }
  func decode(_ type: Int16.Type) throws -> Int16 { try decodeGeneric(type) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeGeneric(type) }
  func decode(_ type: Int32.Type) throws -> Int32 { try decodeGeneric(type) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeGeneric(type) }
  func decode(_ type: Int64.Type) throws -> Int64 { try decodeGeneric(type) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeGeneric(type) }
  func decode(_ type: Float.Type) throws -> Float { try decodeGeneric(type) }
  func decode(_ type: Double.Type) throws -> Double { try decodeGeneric(type) }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    // Data is encoded as a base64 string. It seems odd, but this is how one specializes
    // the decoding of an specific type. For an example see:
    //    https://github.com/swiftlang/swift-foundation/blob/3ab2e47da6a290dbdaefd07429b7a9645c5e592f/Sources/FoundationEssentials/JSON/JSONDecoder.swift#L644-L646
    if type == Data.self { return try self.decodeData() as! T }
    return try impl.decode(type)
  }
}

fileprivate struct InternalKeyedContainer<K: CodingKey> {
  let impl: KeyedDecodingContainer<K>
  let isMap: Bool

  init(_ impl: KeyedDecodingContainer<K>, isMap: Bool = false) {
    self.impl = impl
    self.isMap = isMap
  }

  private func shouldDecodeDefault(forKey key: K) throws -> Bool {
    guard !self.isMap else {
      return false
    }
    if !self.impl.contains(key) {
      return true
    }
    return try self.impl.decodeNil(forKey: key)
  }

  func decodeGeneric<T: Decodable>(_ type: T.Type, forKey key: Self.Key) throws -> T {
    if try self.shouldDecodeDefault(forKey: key) {
      if type == Data.self {
        return Data() as! T
      }
      let decoder = DecodeToDefault()
      return try T(from: decoder)
    }
    if type == Data.self {
      // Data is encoded as a base64 string. It seems odd, but this is how one specializes
      // the decoding of an specific type. For an example see:
      //    https://github.com/swiftlang/swift-foundation/blob/3ab2e47da6a290dbdaefd07429b7a9645c5e592f/Sources/FoundationEssentials/JSON/JSONDecoder.swift#L644-L646
      return try decodeData(forKey: key) as! T
    }
    return try self.impl.decode(Interceptor<T>.self, forKey: key).inner
  }

  func decodeData(forKey key: Self.Key) throws -> Data {
    let string = try self.decode(String.self, forKey: key)
    guard let data = decodeProtoBase64(string) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "Expected a base64 encoded string")
    }
    return data
  }
}

extension InternalKeyedContainer: KeyedDecodingContainerProtocol {
  typealias Key = K
  var allKeys: [K] { self.impl.allKeys }
  var codingPath: [any CodingKey] { self.impl.codingPath }

  func contains(_ key: Key) -> Bool { impl.contains(key) }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Self.Key) throws
    -> KeyedDecodingContainer<NestedKey>
  where NestedKey: CodingKey {
    if try self.shouldDecodeDefault(forKey: key) {
      return KeyedDecodingContainer(DecodeToDefaultKeyed<NestedKey>())
    }
    let impl = try self.impl.nestedContainer(keyedBy: type, forKey: key)
    return KeyedDecodingContainer(InternalKeyedContainer<NestedKey>(impl, isMap: false))
  }

  func nestedUnkeyedContainer(forKey key: Self.Key) throws -> any UnkeyedDecodingContainer {
    if try self.shouldDecodeDefault(forKey: key) {
      return DecodeToDefault()
    }
    let impl = try self.impl.nestedUnkeyedContainer(forKey: key)
    return InternalUnkeyedDecodingContainer(impl)
  }

  func superDecoder() throws -> any Decoder {
    let decoder = try self.impl.superDecoder()
    if !self.isMap,
      let container = try? decoder.singleValueContainer(),
      container.decodeNil()
    {
      return DecodeToDefault()
    }
    return InternalDecoder(impl: decoder, isMap: false)
  }

  func superDecoder(forKey key: K) throws -> any Decoder {
    if try self.shouldDecodeDefault(forKey: key) {
      return DecodeToDefault()
    }
    return InternalDecoder(impl: try self.impl.superDecoder(forKey: key), isMap: false)
  }

  func decode<T: Decodable>(_ type: T.Type, forKey key: Self.Key) throws -> T {
    return try decodeGeneric(type, forKey: key)
  }

  func decodeNil(forKey key: K) throws -> Bool {
    return try self.impl.decodeNil(forKey: key)
  }
}

fileprivate struct InternalUnkeyedDecodingContainer {
  var impl: any UnkeyedDecodingContainer

  init(_ impl: any UnkeyedDecodingContainer) { self.impl = impl }

  mutating func decodeData() throws -> Data {
    let string = try self.decode(String.self)
    guard let data = decodeProtoBase64(string) else {
      throw DecodingError.dataCorruptedError(
        in: self, debugDescription: "Expected a base64 string.")
    }
    return data
  }
}

extension InternalUnkeyedDecodingContainer: UnkeyedDecodingContainer {
  var isAtEnd: Bool { self.impl.isAtEnd }
  var currentIndex: Int { self.impl.currentIndex }
  var count: Int? { self.impl.count }
  var codingPath: [any CodingKey] { self.impl.codingPath }

  mutating func decodeNil() throws -> Bool {
    return try self.impl.decodeNil()
  }

  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    if type == Data.self { return try self.decodeData() as! T }
    return try self.impl.decode(Interceptor<T>.self).inner
  }

  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let impl = try self.impl.nestedUnkeyedContainer()
    return Self(impl)
  }

  mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey>
  where NestedKey: CodingKey {
    let impl = try self.impl.nestedContainer(keyedBy: type)
    return KeyedDecodingContainer(InternalKeyedContainer(impl))
  }

  mutating func superDecoder() throws -> any Decoder {
    return InternalDecoder(impl: try self.impl.superDecoder(), isMap: false)
  }
}

/// An error indicating problems while decoding from a `ProtoJSON` message.
///
/// Google Cloud encodes messages using [ProtoJSON], a specialized form of JSON to represent
/// [Protobuf] data types. This error indicates that it was impossible to decode a data type from
/// the JSON representation.
///
/// [ProtoJSON]: https://protobuf.dev/programming-guides/json/
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
enum ProtoJSONError: Error {
  case unsupportedType(String)
}
