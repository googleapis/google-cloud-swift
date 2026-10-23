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
  public var omitEmptyCollections: Bool = true

  public init() {}

  public func encode<T>(_ value: T) throws -> Data where T: Encodable {
    return try self.encode(value, omitting: [])
  }

  /// Encodes `value`, skipping the fields named in `omitting`.
  ///
  /// Each element of `omitting` is a `.`-separated path of ProtoJSON field names, for example
  /// `secret.name`. Paths that do not match any field are ignored.
  ///
  /// The generated code uses this to skip the request fields bound by the URL path template. Such
  /// fields do not belong in the request body when the method is annotated with `body: "*"`.
  public func encode<T>(_ value: T, omitting: [String]) throws -> Data where T: Encodable {
    let encoder = JSONEncoder()
    encoder.outputFormatting = self.outputFormatting
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    let omit = omitting.isEmpty ? nil : OmitNode(paths: omitting)
    return try encoder.encode(
      Interceptor(inner: value, omit: omit, omitEmptyCollections: self.omitEmptyCollections))
  }
}

/// The field paths skipped by `_ProtoJSONEncoder`, organized as a trie.
///
/// Each level of the trie maps a ProtoJSON field name to the paths skipped below it. Leaf nodes
/// (`terminal`) represent the fields that must not be encoded.
fileprivate struct OmitNode {
  private var terminal = false
  private var children: [String: OmitNode] = [:]

  init() {}

  init(paths: [String]) {
    for path in paths {
      self.insert(path.split(separator: ".").map(String.init)[...])
    }
  }

  /// Returns true if `key` must not be encoded.
  func omits(_ key: String) -> Bool {
    return self.children[key]?.terminal ?? false
  }

  /// Returns the paths skipped below `key`, or `nil` if nothing below `key` is skipped.
  func child(_ key: String) -> OmitNode? {
    guard let node = self.children[key], !node.children.isEmpty else { return nil }
    return node
  }

  private mutating func insert(_ path: ArraySlice<String>) {
    guard let head = path.first else {
      self.terminal = true
      return
    }
    var node = self.children[head] ?? OmitNode()
    node.insert(path.dropFirst())
    self.children[head] = node
  }
}

/// Type-erased protocol used to detect and unwrap `Optional` values passed through generic
/// `encode(_:)` or `encodeIfPresent(_:forKey:)` overloads where the static type `T` is only known
/// to conform to `Encodable` (including nested optionals like `U??`).
protocol _OptionalProtocol {
  /// Returns the innermost wrapped value if non-nil at every optional layer, or `nil` if any layer
  /// is `.none`.
  var _unwrappedEncodable: (any Encodable)? { get }
}

extension Optional: _OptionalProtocol where Wrapped: Encodable {
  var _unwrappedEncodable: (any Encodable)? {
    switch self {
    case .some(let val):
      if let nested = val as? any _OptionalProtocol {
        return nested._unwrappedEncodable
      }
      return val
    case .none:
      return nil
    }
  }
}

/// Abstracts over a concrete encoding destination (keyed at a specific key, unkeyed, or
/// single-value) so the ProtoJSON type-dispatch logic is written once while still invoking
/// specialized primitive overloads on the underlying `JSONEncoder` container and avoiding
/// existential boxing of `Interceptor<T>`.
///
/// The primitive `encodeNil()` and `encode(_:)` requirements match `UnkeyedEncodingContainer` and
/// `SingleValueEncodingContainer` so `InternalUnkeyedEncodingContainer` and
/// `InternalSingleValueEncodingContainer` satisfy them without duplicate methods.
fileprivate protocol _EncodingSink {
  mutating func encodeNil() throws
  mutating func encode(_ value: Bool) throws
  mutating func encode(_ value: String) throws
  mutating func encode(_ value: Double) throws
  mutating func encode(_ value: Float) throws
  mutating func encode(_ value: Int) throws
  mutating func encode(_ value: Int8) throws
  mutating func encode(_ value: Int16) throws
  mutating func encode(_ value: Int32) throws
  mutating func encode(_ value: UInt) throws
  mutating func encode(_ value: UInt8) throws
  mutating func encode(_ value: UInt16) throws
  mutating func encode(_ value: UInt32) throws
  mutating func sink<T: Encodable>(_ value: T) throws
}

extension _EncodingSink {
  /// Applies ProtoJSON encoding rules to `value` and writes it to `self`:
  /// - `Int64` and `UInt64` are converted to `String`.
  /// - `Data` is converted to a base64-encoded `String`.
  /// - Standard JSON scalar types (`String`, `Bool`, `Double`, `Float`, and <=32-bit integers)
  ///   dispatch directly to the concrete primitive overloads on the underlying `JSONEncoder`
  ///   container so its native strategies (such as non-conforming float conversion) apply.
  /// - `Optional` values (checked after concrete scalar casts to avoid a protocol conformance
  ///   lookup on non-optional scalars in `encodeIfPresent`) are recursively unwrapped; if any
  ///   layer is `nil`, either `encodeNil()` is called or the value is omitted depending on
  ///   `encodeNilWhenNil`.
  /// - Composite types (structs, arrays, dictionaries, and custom `Encodable` wrappers) are
  ///   wrapped in `Interceptor` so nested fields and elements are recursively intercepted with
  ///   `omit` and `omitEmptyCollections`.
  @inline(__always)
  mutating func encodeProtoJSON<T: Encodable>(
    _ value: T, omit: OmitNode?, omitEmptyCollections: Bool, encodeNilWhenNil: Bool
  ) throws {
    if let v = value as? Int64 {
      try self.encode(String(v))
    } else if let v = value as? UInt64 {
      try self.encode(String(v))
    } else if let v = value as? String {
      try self.encode(v)
    } else if let v = value as? Bool {
      try self.encode(v)
    } else if let v = value as? Double {
      try self.encode(v)
    } else if let v = value as? Float {
      try self.encode(v)
    } else if let v = value as? Int {
      try self.encode(v)
    } else if let v = value as? Int8 {
      try self.encode(v)
    } else if let v = value as? Int16 {
      try self.encode(v)
    } else if let v = value as? Int32 {
      try self.encode(v)
    } else if let v = value as? UInt {
      try self.encode(v)
    } else if let v = value as? UInt8 {
      try self.encode(v)
    } else if let v = value as? UInt16 {
      try self.encode(v)
    } else if let v = value as? UInt32 {
      try self.encode(v)
    } else if let v = value as? Data {
      try self.encode(v.base64EncodedString())
    } else if let opt = value as? any _OptionalProtocol {
      guard let unwrapped = opt._unwrappedEncodable else {
        if encodeNilWhenNil {
          try self.encodeNil()
        }
        return
      }
      try self.encodeProtoJSON(
        unwrapped, omit: omit, omitEmptyCollections: omitEmptyCollections,
        encodeNilWhenNil: encodeNilWhenNil)
    } else {
      try self.sink(
        Interceptor(inner: value, omit: omit, omitEmptyCollections: omitEmptyCollections))
    }
  }
}

/// Adapts a `KeyedEncodingContainer<K>` bound to a single `key` to `_EncodingSink`.
fileprivate struct _KeyedSink<K: CodingKey>: _EncodingSink {
  var impl: KeyedEncodingContainer<K>
  let key: K

  mutating func encodeNil() throws { try self.impl.encodeNil(forKey: self.key) }
  mutating func encode(_ value: Bool) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: String) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Double) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Float) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Int) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Int8) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Int16) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: Int32) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: UInt) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: UInt8) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: UInt16) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func encode(_ value: UInt32) throws { try self.impl.encode(value, forKey: self.key) }
  mutating func sink<T: Encodable>(_ value: T) throws {
    try self.impl.encode(value, forKey: self.key)
  }
}

protocol _EmptyCollectionProtocol {
  var _isEmptyCollection: Bool { get }
}

extension Array: _EmptyCollectionProtocol {
  var _isEmptyCollection: Bool { self.isEmpty }
}

extension Dictionary: _EmptyCollectionProtocol {
  var _isEmptyCollection: Bool { self.isEmpty }
}

extension Set: _EmptyCollectionProtocol {
  var _isEmptyCollection: Bool { self.isEmpty }
}

fileprivate struct Interceptor<T: Encodable>: Encodable {
  let inner: T
  var omit: OmitNode? = nil
  var omitEmptyCollections: Bool = true

  func encode(to encoder: any Encoder) throws {
    if let d = self.inner as? Data {
      var container = encoder.singleValueContainer()
      try container.encode(d.base64EncodedString())
      return
    }
    try self.inner.encode(
      to: InternalEncoder(
        impl: encoder, omit: self.omit, omitEmptyCollections: self.omitEmptyCollections))
  }
}

fileprivate struct InternalEncoder {
  let impl: any Encoder
  let omit: OmitNode?
  let omitEmptyCollections: Bool

  init(impl: any Encoder, omit: OmitNode? = nil, omitEmptyCollections: Bool = true) {
    self.impl = impl
    self.omit = omit
    self.omitEmptyCollections = omitEmptyCollections
  }
}

extension InternalEncoder: Encoder {
  var codingPath: [any CodingKey] { self.impl.codingPath }
  var userInfo: [CodingUserInfoKey: Any] { self.impl.userInfo }

  func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
    let impl = self.impl.container(keyedBy: type)
    return KeyedEncodingContainer(
      InternalKeyedContainer(
        impl, omit: self.omit, omitEmptyCollections: self.omitEmptyCollections))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    let impl = self.impl.unkeyedContainer()
    return InternalUnkeyedEncodingContainer(
      impl, omitEmptyCollections: self.omitEmptyCollections)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    let impl = self.impl.singleValueContainer()
    return InternalSingleValueEncodingContainer(
      impl, omit: self.omit, omitEmptyCollections: self.omitEmptyCollections)
  }
}

fileprivate struct InternalKeyedContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
  typealias Key = K
  var impl: KeyedEncodingContainer<K>
  var omit: OmitNode?
  var omitEmptyCollections: Bool

  init(
    _ impl: KeyedEncodingContainer<K>, omit: OmitNode? = nil,
    omitEmptyCollections: Bool = true
  ) {
    self.impl = impl
    self.omit = omit
    self.omitEmptyCollections = omitEmptyCollections
  }

  var codingPath: [any CodingKey] { self.impl.codingPath }

  /// Returns true if `key` must not be encoded.
  private func omits(_ key: K) -> Bool {
    return self.omit?.omits(key.stringValue) ?? false
  }

  /// Returns the paths skipped below `key`, or `nil` if nothing below `key` is skipped.
  private func omitted(below key: K) -> OmitNode? {
    return self.omit?.child(key.stringValue)
  }

  mutating func encodeNil(forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encodeNil(forKey: key)
  }

  mutating func encode(_ value: Bool, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: String, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Double, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Float, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int8, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int16, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int32, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: Int64, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(String(value), forKey: key)
  }

  mutating func encode(_ value: UInt, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt8, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt16, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt32, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(value, forKey: key)
  }

  mutating func encode(_ value: UInt64, forKey key: K) throws {
    guard !self.omits(key) else { return }
    try self.impl.encode(String(value), forKey: key)
  }

  /// Encodes an optional value when present.
  ///
  /// In generated code, collection types (repeated fields and maps) are never optional; they are
  /// always declared as non-optional collections (`[T] = []` and `[K: V] = [:]`) and encoded via
  /// `encode(_:forKey:)`.
  ///
  /// `encodeIfPresent` is only called for optional fields (scalars, message structs, and Well-Known
  /// Types such as `WKTStruct?` and `WKTListValue?`). When non-nil, these represent explicitly set
  /// values whose presence must be preserved (e.g., an explicitly set empty `WKTStruct` encodes as
  /// `{}`).
  mutating func encodeIfPresent<T>(_ value: T?, forKey key: K) throws where T: Encodable {
    guard !self.omits(key) else { return }
    guard let value = value else { return }
    var sink = _KeyedSink(impl: self.impl, key: key)
    defer { self.impl = sink.impl }
    try sink.encodeProtoJSON(
      value, omit: self.omitted(below: key), omitEmptyCollections: self.omitEmptyCollections,
      encodeNilWhenNil: false)
  }

  /// Encodes a non-optional value.
  ///
  /// All collection types in generated code (repeated fields and maps) are non-optional and encoded
  /// via this method. When `omitEmptyCollections` is true, empty collections are omitted from the
  /// output to avoid emitting default unpopulated collections in request bodies (e.g. in Compute
  /// Engine PATCH and INSERT operations).
  mutating func encode<T>(_ value: T, forKey key: K) throws where T: Encodable {
    guard !self.omits(key) else { return }
    if self.omitEmptyCollections {
      if let checkable = value as? any _EmptyCollectionProtocol, checkable._isEmptyCollection {
        return
      }
    }
    var sink = _KeyedSink(impl: self.impl, key: key)
    defer { self.impl = sink.impl }
    try sink.encodeProtoJSON(
      value, omit: self.omitted(below: key), omitEmptyCollections: self.omitEmptyCollections,
      encodeNilWhenNil: true)
  }

  mutating func encodeConditional<T>(_ object: T, forKey key: K) throws
  where T: AnyObject, T: Encodable {
    guard !self.omits(key) else { return }
    try self.impl.encodeConditional(object, forKey: key)
  }

  mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let nested = self.impl.nestedContainer(keyedBy: keyType, forKey: key)
    return KeyedEncodingContainer(
      InternalKeyedContainer<NestedKey>(
        nested, omit: self.omitted(below: key),
        omitEmptyCollections: self.omitEmptyCollections))
  }

  mutating func nestedUnkeyedContainer(forKey key: K) -> any UnkeyedEncodingContainer {
    let nested = self.impl.nestedUnkeyedContainer(forKey: key)
    return InternalUnkeyedEncodingContainer(
      nested, omitEmptyCollections: self.omitEmptyCollections)
  }

  mutating func superEncoder() -> any Encoder {
    return InternalEncoder(
      impl: self.impl.superEncoder(), omit: self.omit?.child("super"),
      omitEmptyCollections: self.omitEmptyCollections)
  }

  mutating func superEncoder(forKey key: K) -> any Encoder {
    return InternalEncoder(
      impl: self.impl.superEncoder(forKey: key), omit: self.omitted(below: key),
      omitEmptyCollections: self.omitEmptyCollections)
  }
}

fileprivate struct InternalUnkeyedEncodingContainer: UnkeyedEncodingContainer, _EncodingSink {
  var impl: any UnkeyedEncodingContainer
  var omitEmptyCollections: Bool

  init(_ impl: any UnkeyedEncodingContainer, omitEmptyCollections: Bool = true) {
    self.impl = impl
    self.omitEmptyCollections = omitEmptyCollections
  }

  var codingPath: [any CodingKey] { self.impl.codingPath }
  var count: Int { self.impl.count }

  mutating func sink<T: Encodable>(_ value: T) throws { try self.impl.encode(value) }

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
    try self.encodeProtoJSON(
      value, omit: nil, omitEmptyCollections: self.omitEmptyCollections, encodeNilWhenNil: true)
  }

  mutating func encodeConditional<T>(_ object: T) throws
  where T: AnyObject, T: Encodable {
    try self.impl.encodeConditional(object)
  }

  mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let nested = self.impl.nestedContainer(keyedBy: keyType)
    return KeyedEncodingContainer(
      InternalKeyedContainer<NestedKey>(
        nested, omitEmptyCollections: self.omitEmptyCollections))
  }

  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let nested = self.impl.nestedUnkeyedContainer()
    return InternalUnkeyedEncodingContainer(
      nested, omitEmptyCollections: self.omitEmptyCollections)
  }

  mutating func superEncoder() -> any Encoder {
    return InternalEncoder(
      impl: self.impl.superEncoder(), omitEmptyCollections: self.omitEmptyCollections)
  }
}

fileprivate struct InternalSingleValueEncodingContainer: SingleValueEncodingContainer, _EncodingSink
{
  var impl: any SingleValueEncodingContainer
  var omit: OmitNode?
  var omitEmptyCollections: Bool

  init(
    _ impl: any SingleValueEncodingContainer, omit: OmitNode? = nil,
    omitEmptyCollections: Bool = true
  ) {
    self.impl = impl
    self.omit = omit
    self.omitEmptyCollections = omitEmptyCollections
  }

  var codingPath: [any CodingKey] { self.impl.codingPath }

  mutating func sink<T: Encodable>(_ value: T) throws { try self.impl.encode(value) }

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
    try self.encodeProtoJSON(
      value, omit: self.omit, omitEmptyCollections: self.omitEmptyCollections,
      encodeNilWhenNil: true)
  }
}
