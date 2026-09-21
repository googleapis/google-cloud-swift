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

  /// Compares HTTP field names using ASCII case folding, as required by RFC 9110.
  ///
  /// Deliberately avoids `lowercased()` and `caseInsensitiveCompare`, which apply Unicode case
  /// folding and would treat characters outside the ASCII range as equivalent.
  private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
    let lhs = lhs.utf8
    let rhs = rhs.utf8
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { left, right in
      // Bit 0x20 distinguishes case for ASCII letters, but also for unrelated byte pairs such as
      // "-" (0x2D) and a carriage return (0x0D), so the folded byte must itself be a letter.
      left == right || ((left | 0x20) == (right | 0x20) && (0x61...0x7A).contains(left | 0x20))
    }
  }

  // Equality cannot be synthesized: tuples do not conform to `Equatable`, so neither does the
  // underlying storage.
  public static func == (lhs: AuthHeaders, rhs: AuthHeaders) -> Bool {
    lhs.storage.elementsEqual(rhs.storage, by: ==)
  }
}

extension AuthHeaders: RandomAccessCollection {
  public var startIndex: Int { self.storage.startIndex }

  public var endIndex: Int { self.storage.endIndex }

  public subscript(position: Int) -> Element { self.storage[position] }
}
