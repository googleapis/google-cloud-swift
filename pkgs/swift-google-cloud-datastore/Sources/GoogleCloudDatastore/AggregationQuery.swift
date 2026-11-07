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

public import GoogleWKT

/// A server-side aggregation operation (`COUNT`, `SUM`, or `AVG`).
public struct Aggregation: Sendable, Equatable {
  enum Operator: Sendable, Equatable {
    case count(upTo: Int64?)
    case sum(property: String)
    case avg(property: String)
  }

  /// The alias used to look up this aggregation's result in ``AggregationResults``.
  public let alias: String
  let op: Operator

  init(alias: String, op: Operator) {
    self.alias = alias
    self.op = op
  }

  /// Counts matching entities, optionally capped at `upTo`.
  public static func count(alias: String = "count", upTo: Int64? = nil) -> Self {
    Self(alias: alias, op: .count(upTo: upTo))
  }

  /// Computes the sum of a numeric property across matching entities.
  public static func sum(_ property: String, alias: String? = nil) -> Self {
    Self(alias: alias ?? "sum_\(property)", op: .sum(property: property))
  }

  /// Computes the arithmetic mean of a numeric property across matching entities.
  public static func avg(_ property: String, alias: String? = nil) -> Self {
    Self(alias: alias ?? "avg_\(property)", op: .avg(property: property))
  }
}

/// An aggregation query wrapping a structured ``Query`` or ``GqlQuery``.
public struct AggregationQuery: Sendable, Equatable {
  /// The underlying query being aggregated.
  public enum BaseQuery: Sendable, Equatable {
    case structured(Query)
    case gql(GqlQuery)
  }

  /// The base query over which aggregations are computed.
  public var baseQuery: BaseQuery
  /// The aggregations to compute.
  public var aggregations: [Aggregation]

  /// Creates an ``AggregationQuery`` over a structured ``Query``.
  public init(over query: Query, aggregations: [Aggregation] = []) {
    self.baseQuery = .structured(query)
    self.aggregations = aggregations
  }

  /// Creates an ``AggregationQuery`` over a ``GqlQuery``.
  public init(over gqlQuery: GqlQuery, aggregations: [Aggregation] = []) {
    self.baseQuery = .gql(gqlQuery)
    self.aggregations = aggregations
  }

  /// Appends a `COUNT` aggregation.
  public func count(alias: String = "count", upTo: Int64? = nil) -> Self {
    var copy = self
    copy.aggregations.append(.count(alias: alias, upTo: upTo))
    return copy
  }

  /// Appends a `SUM` aggregation on `property`.
  public func sum(_ property: String, alias: String? = nil) -> Self {
    var copy = self
    copy.aggregations.append(.sum(property, alias: alias))
    return copy
  }

  /// Appends an `AVG` aggregation on `property`.
  public func avg(_ property: String, alias: String? = nil) -> Self {
    var copy = self
    copy.aggregations.append(.avg(property, alias: alias))
    return copy
  }
}

/// Results returned by `runAggregationQuery`.
public struct AggregationResults: Sendable, Equatable {
  /// Map of aggregation alias to its computed ``PropertyValue``.
  public let values: [String: PropertyValue]
  /// Snapshot timestamp at which the aggregation was evaluated.
  public let readTime: GoogleWKT.WKTTimestamp?

  /// Creates ``AggregationResults``.
  public init(values: [String: PropertyValue], readTime: GoogleWKT.WKTTimestamp? = nil) {
    self.values = values
    self.readTime = readTime
  }

  /// Looks up the computed ``Value`` for the given `alias`.
  public subscript(alias: String) -> Value? {
    values[alias]?.value
  }
}
