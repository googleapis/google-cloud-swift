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
fileprivate protocol _OptionalProtocol {
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

/// The result of preparing an arbitrary `Encodable` value for ProtoJSON encoding.
fileprivate enum BoxedValue {
  /// The value was an `Optional` (possibly multi-layered) whose underlying value was `nil`.
  case nilValue
  /// The non-nil value transformed for the underlying `JSONEncoder` container.
  case value(any Encodable)
}

/// Unwraps any optional layers from `value` and applies ProtoJSON encoding rules:
/// - `Int64` and `UInt64` are converted to `String`.
/// - `Data` is converted to a base64-encoded `String`.
/// - Standard JSON scalar types (`String`, `Bool`, `Double`, `Float`, and <=32-bit integers) are
///   passed directly to `JSONEncoder` so its native strategies (such as non-conforming float
///   conversion) apply.
/// - Composite types (structs, arrays, dictionaries, and custom `Encodable` wrappers) are wrapped
///   in `Interceptor` so nested fields and elements are recursively intercepted with `omit` and
///   `omitEmptyCollections`.
fileprivate func box(
  _ value: any Encodable, omit: OmitNode? = nil, omitEmptyCollections: Bool = true
) -> BoxedValue {
  let unwrapped: any Encodable
  if let opt = value as? any _OptionalProtocol {
    guard let inner = opt._unwrappedEncodable else { return .nilValue }
    unwrapped = inner
  } else {
    unwrapped = value
  }
  switch unwrapped {
  case let v as Int64:
    return .value(String(v))
  case let v as UInt64:
    return .value(String(v))
  case let v as Data:
    return .value(v.base64EncodedString())
  case is String, is Bool, is Double, is Float,
    is Int, is Int8, is Int16, is Int32,
    is UInt, is UInt8, is UInt16, is UInt32:
    return .value(unwrapped)
  default:
    return .value(
      makeInterceptor(unwrapped, omit: omit, omitEmptyCollections: omitEmptyCollections))
  }
}

/// Opens the existential `any Encodable` to construct a generic `Interceptor<T>`.
fileprivate func makeInterceptor<T: Encodable>(
  _ value: T, omit: OmitNode?, omitEmptyCollections: Bool
) -> any Encodable {
  Interceptor(inner: value, omit: omit, omitEmptyCollections: omitEmptyCollections)
}

fileprivate protocol _EmptyCollectionProtocol {
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
    switch box(
      value, omit: self.omitted(below: key), omitEmptyCollections: self.omitEmptyCollections)
    {
    case .nilValue:
      return
    case .value(let boxed):
      try self.impl.encode(boxed, forKey: key)
    }
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
    switch box(
      value, omit: self.omitted(below: key), omitEmptyCollections: self.omitEmptyCollections)
    {
    case .nilValue:
      try self.impl.encodeNil(forKey: key)
    case .value(let boxed):
      try self.impl.encode(boxed, forKey: key)
    }
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
      impl: self.impl.superEncoder(), omitEmptyCollections: self.omitEmptyCollections)
  }

  mutating func superEncoder(forKey key: K) -> any Encoder {
    return InternalEncoder(
      impl: self.impl.superEncoder(forKey: key), omit: self.omitted(below: key),
      omitEmptyCollections: self.omitEmptyCollections)
  }
}

fileprivate struct InternalUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  var impl: any UnkeyedEncodingContainer
  var omitEmptyCollections: Bool

  init(_ impl: any UnkeyedEncodingContainer, omitEmptyCollections: Bool = true) {
    self.impl = impl
    self.omitEmptyCollections = omitEmptyCollections
  }

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
    switch box(value, omitEmptyCollections: self.omitEmptyCollections) {
    case .nilValue:
      try self.impl.encodeNil()
    case .value(let boxed):
      try self.impl.encode(boxed)
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

fileprivate struct InternalSingleValueEncodingContainer: SingleValueEncodingContainer {
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
    switch box(value, omit: self.omit, omitEmptyCollections: self.omitEmptyCollections) {
    case .nilValue:
      try self.impl.encodeNil()
    case .value(let boxed):
      try self.impl.encode(boxed)
    }
  }
}
