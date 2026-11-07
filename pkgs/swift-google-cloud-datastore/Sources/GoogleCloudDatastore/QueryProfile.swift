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

/// Summary of the query plan selected by the Datastore query planner.
public struct PlanSummary: Sendable, Equatable {
  /// Structured dictionaries describing each index used by the query plan.
  public let indexesUsed: [GoogleWKT.WKTStruct]

  /// Creates a ``PlanSummary``.
  public init(indexesUsed: [GoogleWKT.WKTStruct]) {
    self.indexesUsed = indexesUsed
  }
}

/// Runtime execution statistics returned when `analyze: true` is specified.
public struct ExecutionStats: Sendable, Equatable {
  /// Total number of results returned (entities or aggregation rows).
  public let resultsReturned: Int64
  /// Total server-side execution duration.
  public let executionDuration: GoogleWKT.WKTDuration?
  /// Total number of index/entity read operations billed by the query.
  public let readOperations: Int64
  /// Additional diagnostic statistics.
  public let debugStats: GoogleWKT.WKTStruct?

  /// Creates ``ExecutionStats``.
  public init(
    resultsReturned: Int64,
    executionDuration: GoogleWKT.WKTDuration? = nil,
    readOperations: Int64,
    debugStats: GoogleWKT.WKTStruct? = nil
  ) {
    self.resultsReturned = resultsReturned
    self.executionDuration = executionDuration
    self.readOperations = readOperations
    self.debugStats = debugStats
  }
}

/// Query planner and runtime metrics returned by `explainQuery` and `explainAggregationQuery`.
public struct ExplainMetrics: Sendable, Equatable {
  /// Query plan summary (always present when planning succeeds).
  public let planSummary: PlanSummary?
  /// Runtime execution statistics (present only when `analyze == true`).
  public let executionStats: ExecutionStats?

  /// Creates ``ExplainMetrics``.
  public init(planSummary: PlanSummary? = nil, executionStats: ExecutionStats? = nil) {
    self.planSummary = planSummary
    self.executionStats = executionStats
  }
}

/// Result of profiling a query with `explainQuery`.
public struct QueryExplainResult: Sendable, Equatable {
  /// All entities matched by the query (empty when `analyze == false`).
  public let entities: [Entity]
  /// The final pagination cursor after draining the query, if any.
  public let endCursor: Cursor?
  /// The query plan summary and (if `analyze == true`) execution statistics.
  public let metrics: ExplainMetrics

  /// Creates a ``QueryExplainResult``.
  public init(entities: [Entity], endCursor: Cursor? = nil, metrics: ExplainMetrics) {
    self.entities = entities
    self.endCursor = endCursor
    self.metrics = metrics
  }
}

/// Result of profiling an aggregation query with `explainAggregationQuery`.
public struct AggregationExplainResult: Sendable, Equatable {
  /// The computed aggregation results (`nil` when `analyze == false`).
  public let results: AggregationResults?
  /// The query plan summary and (if `analyze == true`) execution statistics.
  public let metrics: ExplainMetrics

  /// Creates an ``AggregationExplainResult``.
  public init(results: AggregationResults? = nil, metrics: ExplainMetrics) {
    self.results = results
    self.metrics = metrics
  }
}
