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

  /// Returns whether two collections hold the same header fields in the same order.
  ///
  /// This cannot be synthesized: tuples do not conform to `Equatable`, so neither does the
  /// underlying storage.
  public static func == (lhs: AuthHeaders, rhs: AuthHeaders) -> Bool {
    lhs.storage.count == rhs.storage.count
      && zip(lhs.storage, rhs.storage).allSatisfy { $0 == $1 }
  }
}

extension AuthHeaders: RandomAccessCollection {
  public var startIndex: Int { self.storage.startIndex }

  public var endIndex: Int { self.storage.endIndex }

  public subscript(position: Int) -> Element { self.storage[position] }
}
