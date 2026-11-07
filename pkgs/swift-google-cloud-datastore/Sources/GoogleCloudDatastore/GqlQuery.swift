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

/// A parameter bound to a named (`@foo`) or positional (`@1`) placeholder in a ``GqlQuery``.
public enum GqlQueryParameter: Sendable, Equatable {
  /// Binds a Datastore ``Value``.
  case value(Value)
  /// Binds a pagination ``Cursor``.
  case cursor(Cursor)
}

/// A GraphQL-like Datastore Query Language statement (`google.datastore.v1.GqlQuery`).
public struct GqlQuery: Sendable, Equatable {
  /// The GQL query string (e.g., `"SELECT * FROM Task WHERE done = @done ORDER BY created DESC"`).
  public var queryString: String
  /// If `false` (the default), literal constants in `queryString` are rejected to prevent injection.
  public var allowLiterals: Bool
  /// Named parameter bindings (`@name` -> ``GqlQueryParameter``).
  public var namedBindings: [String: GqlQueryParameter]
  /// Positional parameter bindings (`@1`, `@2`, ... -> ``GqlQueryParameter``).
  public var positionalBindings: [GqlQueryParameter]
  /// Optional namespace override (defaults to the client's `namespaceId` if `nil`).
  public var namespaceId: String?

  /// Creates a ``GqlQuery``.
  public init(
    _ queryString: String,
    allowLiterals: Bool = false,
    namedBindings: [String: GqlQueryParameter] = [:],
    positionalBindings: [GqlQueryParameter] = [],
    namespaceId: String? = nil
  ) {
    self.queryString = queryString
    self.allowLiterals = allowLiterals
    self.namedBindings = namedBindings
    self.positionalBindings = positionalBindings
    self.namespaceId = namespaceId
  }
}
