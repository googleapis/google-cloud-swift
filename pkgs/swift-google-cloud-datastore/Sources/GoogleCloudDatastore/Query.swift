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
public import GoogleWKT

/// Sort direction for a ``PropertyOrder``.
public enum SortDirection: Sendable, Hashable {
  case ascending, descending
}

/// Specifies a sort order on a property.
public struct PropertyOrder: Sendable, Equatable {
  public var property: String
  public var direction: SortDirection

  public init(property: String, direction: SortDirection = .ascending) {
    self.property = property
    self.direction = direction
  }

  public static func ascending(_ property: String) -> Self {
    Self(property: property, direction: .ascending)
  }

  public static func descending(_ property: String) -> Self {
    Self(property: property, direction: .descending)
  }
}

/// A filter predicate in a structured ``Query``.
public indirect enum Filter: Sendable, Equatable {
  /// Comparison operators for `PropertyFilter`.
  public enum Operator: Sendable, Hashable {
    case lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual
    case equal, notEqual, `in`, notIn, hasAncestor
  }

  case property(name: String, op: Operator, value: Value)
  case and([Filter])
  case or([Filter])

  public static func equal(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .equal, value: value)
  }
  public static func notEqual(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .notEqual, value: value)
  }
  public static func lessThan(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .lessThan, value: value)
  }
  public static func lessThanOrEqual(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .lessThanOrEqual, value: value)
  }
  public static func greaterThan(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .greaterThan, value: value)
  }
  public static func greaterThanOrEqual(_ name: String, _ value: Value) -> Self {
    .property(name: name, op: .greaterThanOrEqual, value: value)
  }
  public static func `in`(_ name: String, _ values: [Value]) -> Self {
    .property(name: name, op: .in, value: .array(values.map { PropertyValue($0) }))
  }
  public static func notIn(_ name: String, _ values: [Value]) -> Self {
    .property(name: name, op: .notIn, value: .array(values.map { PropertyValue($0) }))
  }
  public static func hasAncestor(_ ancestorKey: Key) -> Self {
    .property(name: "__key__", op: .hasAncestor, value: .key(ancestorKey))
  }
}

/// An opaque pagination cursor returned by Datastore query batches.
public struct Cursor: Sendable, Hashable, Codable {
  public let bytes: Data

  public init(bytes: Data) {
    self.bytes = bytes
  }

  /// Encodes the cursor bytes as a URL-safe Base64 string.
  public func toUrlSafe() -> String {
    bytes.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Decodes a cursor from a URL-safe (or standard) Base64 string.
  public init(urlSafe: String) throws {
    var base64 =
      urlSafe
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }
    guard let decoded = Data(base64Encoded: base64) else {
      throw DatastoreError.invalidArgument("Invalid base64 cursor string")
    }
    self.bytes = decoded
  }
}

/// A structured Cloud Datastore query (`google.datastore.v1.Query`).
public struct Query: Sendable, Equatable {
  public var kind: String?
  public var namespaceId: String?
  public var filter: Filter?
  public var projection: [String]
  public var distinctOn: [String]
  public var order: [PropertyOrder]
  public var startCursor: Cursor?
  public var endCursor: Cursor?
  public var offset: Int32
  public var limit: Int32?

  public init(
    kind: String? = nil,
    namespaceId: String? = nil,
    filter: Filter? = nil,
    projection: [String] = [],
    distinctOn: [String] = [],
    order: [PropertyOrder] = [],
    startCursor: Cursor? = nil,
    endCursor: Cursor? = nil,
    offset: Int32 = 0,
    limit: Int32? = nil
  ) {
    self.kind = kind
    self.namespaceId = namespaceId
    self.filter = filter
    self.projection = projection
    self.distinctOn = distinctOn
    self.order = order
    self.startCursor = startCursor
    self.endCursor = endCursor
    self.offset = offset
    self.limit = limit
  }

  public func filter(_ newFilter: Filter) -> Self {
    var copy = self
    if let existing = copy.filter {
      if case .and(var list) = existing {
        list.append(newFilter)
        copy.filter = .and(list)
      } else {
        copy.filter = .and([existing, newFilter])
      }
    } else {
      copy.filter = newFilter
    }
    return copy
  }

  public func hasAncestor(_ ancestor: Key) -> Self { filter(.hasAncestor(ancestor)) }

  public func project(_ properties: [String]) -> Self {
    var copy = self
    copy.projection = properties
    return copy
  }

  public func keysOnly() -> Self { project(["__key__"]) }

  public func distinctOn(_ properties: [String]) -> Self {
    var copy = self
    copy.distinctOn = properties
    return copy
  }

  public func order(by property: String, direction: SortDirection = .ascending) -> Self {
    var copy = self
    copy.order.append(PropertyOrder(property: property, direction: direction))
    return copy
  }

  public func start(at cursor: Cursor) -> Self {
    var copy = self
    copy.startCursor = cursor
    return copy
  }

  public func end(at cursor: Cursor) -> Self {
    var copy = self
    copy.endCursor = cursor
    return copy
  }

  public func offset(_ offset: Int32) -> Self {
    var copy = self
    copy.offset = offset
    return copy
  }

  public func limit(_ limit: Int32) -> Self {
    var copy = self
    copy.limit = limit
    return copy
  }
}

/// A single entity result paired with its resumption cursor inside a ``QueryBatch``.
public struct EntityItem: Sendable, Equatable {
  public let entity: Entity
  public let cursor: Cursor?

  public init(entity: Entity, cursor: Cursor? = nil) {
    self.entity = entity
    self.cursor = cursor
  }
}

/// Terminal state of a ``QueryBatch``.
public enum MoreResultsType: Sendable, Hashable {
  case notFinished, moreResultsAfterLimit, moreResultsAfterCursor, noMoreResults
}

/// A batch of query results returned by `runQueryBatches`.
public struct QueryBatch: Sendable, Equatable {
  public let items: [EntityItem]
  public let skippedResults: Int32
  public let skippedCursor: Cursor?
  public let endCursor: Cursor?
  public let moreResults: MoreResultsType
  public let readTime: GoogleWKT.WKTTimestamp?

  public init(
    items: [EntityItem],
    skippedResults: Int32 = 0,
    skippedCursor: Cursor? = nil,
    endCursor: Cursor? = nil,
    moreResults: MoreResultsType = .noMoreResults,
    readTime: GoogleWKT.WKTTimestamp? = nil
  ) {
    self.items = items
    self.skippedResults = skippedResults
    self.skippedCursor = skippedCursor
    self.endCursor = endCursor
    self.moreResults = moreResults
    self.readTime = readTime
  }
}
