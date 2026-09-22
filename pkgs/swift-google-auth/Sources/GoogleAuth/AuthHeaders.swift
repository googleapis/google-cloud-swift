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

/// The HTTP request header fields required to authenticate a Google Cloud API request.
///
/// An ordered collection of name-value pairs that permits repeated header names, mirroring the
/// wire format of HTTP header fields. Common headers produced include:
/// - `Authorization: Bearer <token>`: An OAuth 2.0 access token or self-signed JWT.
/// - `x-goog-api-key: <key>`: An API key identifying the calling project.
/// - `x-goog-user-project: <project-id>`: An optional project ID used for billing and quota attribution.
///
/// Iterate the headers to apply them to a request:
///
/// ```swift
/// let headers = try await credentials.headers()
/// for (name, value) in headers {
///   request.addHeader(name: name, value: value)
/// }
/// ```
///
/// Two collections are equal when they hold the same fields in the same order, comparing names
/// and values exactly. Equality is case-sensitive even though HTTP field names are not, because
/// the value carries the exact bytes that will be written to the wire. Use ``subscript(_:)``,
/// ``values(for:)``, or ``contains(name:)`` to look a field up by name case-insensitively.
public struct AuthHeaders: Sendable, Equatable, ExpressibleByArrayLiteral {
  /// A single header field, as a name-value pair.
  public typealias Element = (name: String, value: String)

  private var storage: [Element]

  /// The number of header fields in the collection.
  public var count: Int { self.storage.count }

  /// A Boolean value indicating whether the collection is empty.
  public var isEmpty: Bool { self.storage.isEmpty }

  /// Creates an empty collection of headers.
  public init() {
    self.storage = []
  }

  /// Creates a collection from an ordered list of header fields.
  ///
  /// - Parameter headers: The header fields, in the order they should be applied.
  public init(_ headers: [Element]) {
    self.storage = headers
  }

  /// Creates a collection from an array literal of header fields.
  ///
  /// - Parameter elements: The header fields, in the order they should be applied.
  public init(arrayLiteral elements: Element...) {
    self.storage = elements
  }

  /// Appends a header field, preserving any existing field with the same name.
  ///
  /// - Parameters:
  ///   - name: The header field name.
  ///   - value: The header field value.
  public mutating func append(name: String, value: String) {
    self.storage.append((name: name, value: value))
  }

  /// The value of the first field whose name matches `name`, ignoring case.
  ///
  /// - Parameter name: The header field name to look up.
  /// - Returns: The matching value, or `nil` when no field has that name.
  public subscript(name: String) -> String? {
    self.storage.first { Self.namesMatch($0.name, name) }?.value
  }

  /// The values of every field whose name matches `name`, ignoring case, in order.
  ///
  /// - Parameter name: The header field name to look up.
  /// - Returns: The matching values, or an empty array when no field has that name.
  public func values(for name: String) -> [String] {
    self.storage
      .filter { Self.namesMatch($0.name, name) }
      .map(\.value)
  }

  /// Returns whether any field has the given name, ignoring case.
  ///
  /// - Parameter name: The header field name to look up.
  public func contains(name: String) -> Bool {
    self.storage.contains { Self.namesMatch($0.name, name) }
  }

  /// Compares HTTP field names case-insensitively, as RFC 9110 requires.
  ///
  /// Folds ASCII case only. `lowercased()` and `caseInsensitiveCompare` apply Unicode case
  /// folding, which would match "İ" (U+0130) against "i".
  private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
    guard lhs.utf8.count == rhs.utf8.count else { return false }
    return lhs.utf8.elementsEqual(rhs.utf8) { toASCIILower($0) == toASCIILower($1) }
  }

  /// Returns the lowercase form of an ASCII letter, leaving every other byte unchanged.
  private static func toASCIILower(_ byte: UInt8) -> UInt8 {
    (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
  }

  // Equality cannot be synthesized: tuples do not conform to `Equatable`, so neither does the
  // underlying storage.
  public static func == (lhs: AuthHeaders, rhs: AuthHeaders) -> Bool {
    guard lhs.storage.count == rhs.storage.count else { return false }
    return lhs.storage.elementsEqual(rhs.storage, by: ==)
  }
}

extension AuthHeaders: Sequence {
  public func makeIterator() -> IndexingIterator<[Element]> {
    self.storage.makeIterator()
  }
}
