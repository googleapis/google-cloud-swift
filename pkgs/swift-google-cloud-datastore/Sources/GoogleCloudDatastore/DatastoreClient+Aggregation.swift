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

import DatastoreV1Stub
import Foundation
import GoogleGax

extension Aggregation {
  func toProto() -> DatastoreV1Stub.AggregationQuery.Aggregation {
    DatastoreV1Stub.AggregationQuery.Aggregation().with { proto in
      proto.alias = alias
      switch op {
      case .count(let upTo):
        proto.operator = .count(
          DatastoreV1Stub.AggregationQuery.Aggregation.Count().with { c in
            c.upTo = upTo
          }
        )
      case .sum(let property):
        proto.operator = .sum(
          DatastoreV1Stub.AggregationQuery.Aggregation.Sum().with { s in
            s.property = DatastoreV1Stub.PropertyReference().with { $0.name = property }
          }
        )
      case .avg(let property):
        proto.operator = .avg(
          DatastoreV1Stub.AggregationQuery.Aggregation.Avg().with { a in
            a.property = DatastoreV1Stub.PropertyReference().with { $0.name = property }
          }
        )
      }
    }
  }
}

extension DatastoreClient {
  func executeAggregationQuery(
    query: AggregationQuery,
    wireReadOptions: DatastoreV1Stub.ReadOptions?,
    explainOptions: DatastoreV1Stub.ExplainOptions?,
    requestOptions: GoogleGax.RequestOptions?,
    onFirstResponse: (@Sendable (Data) -> Void)? = nil
  ) async throws -> (results: AggregationResults, explainMetrics: ExplainMetrics?) {
    let effectiveNs: String
    let wireQueryType: DatastoreV1Stub.RunAggregationQueryRequest.QueryTypeOneOf

    switch query.baseQuery {
    case .structured(let baseQuery):
      effectiveNs = baseQuery.namespaceId ?? namespaceId
      let nested = try baseQuery.toProto(
        defaultProjectId: projectId,
        defaultDatabaseId: databaseId,
        defaultNamespaceId: effectiveNs
      )
      wireQueryType = .aggregationQuery(
        DatastoreV1Stub.AggregationQuery().with {
          $0.queryType = .nestedQuery(nested)
          $0.aggregations = query.aggregations.map { $0.toProto() }
        })
    case .gql(let gqlQuery):
      effectiveNs = gqlQuery.namespaceId ?? namespaceId
      wireQueryType = .gqlQuery(
        try gqlQuery.toProto(
          defaultProjectId: projectId,
          defaultDatabaseId: databaseId,
          defaultNamespaceId: effectiveNs
        ))
    }
    let wirePartition = PartitionId(
      projectId: projectId, databaseId: databaseId, namespaceId: effectiveNs
    ).toProto()

    let request = DatastoreV1Stub.RunAggregationQueryRequest().with {
      $0.projectId = projectId
      $0.databaseId = databaseId
      $0.partitionId = wirePartition
      $0.readOptions = wireReadOptions
      $0.explainOptions = explainOptions
      $0.queryType = wireQueryType
    }

    let response = try await stub.runAggregationQuery(
      request: request,
      options: effectiveRequestOptions(requestOptions)
    )
    if !response.transaction.isEmpty {
      onFirstResponse?(response.transaction)
    }

    var values: [String: PropertyValue] = [:]
    if let batch = response.batch {
      for aggResult in batch.aggregationResults {
        for (alias, wireVal) in aggResult.aggregateProperties {
          values[alias] = try PropertyValue(fromProto: wireVal)
        }
      }
    }
    let aggResults = AggregationResults(
      values: values,
      readTime: response.batch?.readTime
    )
    let metrics = response.explainMetrics.map(ExplainMetrics.init(fromProto:))
    return (aggResults, metrics)
  }
}
