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
import GoogleWKT
import Synchronization
import Testing

@testable import GoogleCloudDatastore

private func makeWireEntityResult(
  partitionId: DatastoreV1Stub.PartitionId?,
  kind: String,
  id: Int64,
  projectedMicros: Int64? = nil
) -> DatastoreV1Stub.EntityResult {
  DatastoreV1Stub.EntityResult().with {
    $0.cursor = Data([UInt8(id & 0xFF)])
    $0.entity = DatastoreV1Stub.Entity().with {
      $0.key = DatastoreV1Stub.Key().with {
        $0.partitionId = partitionId
        $0.path = [
          DatastoreV1Stub.Key.PathElement().with {
            $0.kind = kind
            $0.idType = .id(id)
          }
        ]
      }
      if let micros = projectedMicros {
        $0.properties = [
          "ts": DatastoreV1Stub.Value().with {
            $0.meaning = 18
            $0.valueType = .integerValue(micros)
          }
        ]
      }
    }
  }
}

@Suite struct QueryAndAggregationTests {
  @Test func structuredQueryMultiBatchContinuationAndProjectedTimestamp() async throws {
    let stub = MockDatastoreStub()
    let callCounter = Mutex(0)
    let skippedCur = Data([0x0A, 0x0B])
    let batch1EndCur = Data([0x1A, 0x1B])
    let batch2EndCur = Data([0x2A, 0x2B])

    stub.state.withLock { s in
      s.runQueryHandler = { req in
        let callNum = callCounter.withLock { c -> Int in
          c += 1
          return c
        }
        if callNum == 1 {
          return DatastoreV1Stub.RunQueryResponse().with {
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.skippedResults = 3
              $0.skippedCursor = skippedCur
              $0.moreResults = .notFinished
            }
          }
        } else if callNum == 2 {
          return DatastoreV1Stub.RunQueryResponse().with {
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.skippedResults = 2
              $0.entityResultType = .projection
              $0.entityResults = [
                makeWireEntityResult(
                  partitionId: req.partitionId, kind: "Event", id: 1,
                  projectedMicros: 1_700_000_000_000_000),
                makeWireEntityResult(
                  partitionId: req.partitionId, kind: "Event", id: 2,
                  projectedMicros: 1_700_000_001_000_000),
              ]
              $0.endCursor = batch1EndCur
              $0.moreResults = .notFinished
            }
          }
        } else {
          return DatastoreV1Stub.RunQueryResponse().with {
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.entityResultType = .projection
              $0.entityResults = [
                makeWireEntityResult(
                  partitionId: req.partitionId, kind: "Event", id: 3,
                  projectedMicros: 1_700_000_002_000_000)
              ]
              $0.endCursor = batch2EndCur
              $0.moreResults = .moreResultsAfterLimit
            }
          }
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-q", namespaceId: "default-ns"),
      stub: stub
    )

    let query = Query(kind: "Event", namespaceId: "custom-ns")
      .filter(.equal("active", true))
      .filter(.or([.greaterThan("score", 10), .lessThan("score", 0)]))
      .project(["ts"])
      .distinctOn(["ts"])
      .order(by: "ts", direction: .ascending)
      .offset(5)
      .limit(3)

    var entities: [GoogleCloudDatastore.Entity] = []
    for try await entity in client.runQuery(query) {
      entities.append(entity)
    }

    #expect(entities.count == 3)
    #expect(entities.map { $0.key.id } == [.id(1), .id(2), .id(3)])
    #expect(entities[0]["ts"]?.projectedTimestamp?.seconds == 1_700_000_000)
    #expect(entities[2]["ts"]?.projectedTimestamp?.seconds == 1_700_000_002)

    let sentReqs = stub.state.withLock { $0.runQueryCalls.map(\.0) }
    #expect(sentReqs.count == 3)
    #expect(sentReqs[0].partitionId?.namespaceId == "custom-ns")

    if case .query(let q1) = sentReqs[0].queryType,
      case .query(let q2) = sentReqs[1].queryType,
      case .query(let q3) = sentReqs[2].queryType
    {
      #expect(q1.offset == 5 && q1.limit == 3)
      #expect(q2.offset == 2 && q2.startCursor == skippedCur && q2.limit == 3)
      #expect(q3.offset == 0 && q3.startCursor == batch1EndCur && q3.limit == 1)
    } else {
      Issue.record("Expected all three requests to carry structured Query")
    }
  }

  @Test func gqlQueryParameterBindingsAndCompiledQueryContinuation() async throws {
    let stub = MockDatastoreStub()
    let endCur = Data([0xDE, 0xAD])
    let callCounter = Mutex(0)

    stub.state.withLock { s in
      s.runQueryHandler = { req in
        let callNum = callCounter.withLock { c -> Int in
          c += 1
          return c
        }
        if callNum == 1 {
          return DatastoreV1Stub.RunQueryResponse().with {
            $0.query = DatastoreV1Stub.Query().with {
              $0.kind = [DatastoreV1Stub.KindExpression().with { $0.name = "Task" }]
            }
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.entityResults = [
                makeWireEntityResult(partitionId: req.partitionId, kind: "Task", id: 10)
              ]
              $0.endCursor = endCur
              $0.moreResults = .notFinished
            }
          }
        } else {
          return DatastoreV1Stub.RunQueryResponse().with {
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.entityResults = [
                makeWireEntityResult(partitionId: req.partitionId, kind: "Task", id: 20)
              ]
              $0.moreResults = .noMoreResults
            }
          }
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-gql"),
      stub: stub
    )

    let gql = GqlQuery(
      "SELECT * FROM Task WHERE done = @done AND __key__ > @1",
      allowLiterals: false,
      namedBindings: ["done": .value(false)],
      positionalBindings: [.cursor(Cursor(bytes: Data([0x01])))]
    )

    var batches: [QueryBatch] = []
    for try await batch in client.runQueryBatches(gql) {
      batches.append(batch)
    }

    #expect(batches.count == 2)
    #expect(batches[0].endCursor == Cursor(bytes: endCur))
    #expect(batches[0].moreResults == .notFinished)
    #expect(batches[1].moreResults == .noMoreResults)

    let sentReqs = stub.state.withLock { $0.runQueryCalls.map(\.0) }
    #expect(sentReqs.count == 2)
    if case .gqlQuery(let wireGql) = sentReqs[0].queryType {
      #expect(
        wireGql.namedBindings["done"]?.parameterType
          == .value(DatastoreV1Stub.Value().with { $0.valueType = .booleanValue(false) })
      )
      #expect(wireGql.positionalBindings.first?.parameterType == .cursor(Data([0x01])))
    } else {
      Issue.record("Expected first request to carry gqlQuery")
    }

    if case .query(let compiled) = sentReqs[1].queryType {
      #expect(compiled.kind.first?.name == "Task" && compiled.startCursor == endCur)
    } else {
      Issue.record("Expected second request to carry compiled structured Query")
    }
  }

  @Test func aggregationQueriesAndExplainProfiling() async throws {
    let stub = MockDatastoreStub()
    let readTs = try GoogleWKT.WKTTimestamp(seconds: 1_700_000_500, nanos: 0)

    stub.state.withLock { s in
      s.runAggregationQueryHandler = { req in
        DatastoreV1Stub.RunAggregationQueryResponse().with {
          $0.batch = DatastoreV1Stub.AggregationResultBatch().with {
            $0.readTime = readTs
            $0.aggregationResults = [
              DatastoreV1Stub.AggregationResult().with {
                $0.aggregateProperties = [
                  "total": DatastoreV1Stub.Value().with { $0.valueType = .integerValue(42) },
                  "sum_hours": DatastoreV1Stub.Value().with { $0.valueType = .integerValue(120) },
                  "avg_score": DatastoreV1Stub.Value().with { $0.valueType = .doubleValue(4.75) },
                ]
              }
            ]
          }
          if let explain = req.explainOptions {
            $0.explainMetrics = DatastoreV1Stub.ExplainMetrics().with {
              $0.planSummary = DatastoreV1Stub.PlanSummary().with {
                $0.indexesUsed = [["query_scope": .string("Collection")]]
              }
              if explain.analyze {
                $0.executionStats = DatastoreV1Stub.ExecutionStats().with {
                  $0.resultsReturned = 1
                  $0.readOperations = 42
                }
              }
            }
          }
        }
      }

      s.runQueryHandler = { req in
        DatastoreV1Stub.RunQueryResponse().with {
          if req.explainOptions?.analyze == true {
            $0.batch = DatastoreV1Stub.QueryResultBatch().with {
              $0.entityResults = [
                makeWireEntityResult(partitionId: req.partitionId, kind: "Task", id: 1)
              ]
              $0.endCursor = Data([0x99])
              $0.moreResults = .noMoreResults
            }
          }
          $0.explainMetrics = DatastoreV1Stub.ExplainMetrics().with {
            $0.planSummary = DatastoreV1Stub.PlanSummary().with {
              $0.indexesUsed = [["properties": .string("(done ASC)")]]
            }
            if req.explainOptions?.analyze == true {
              $0.executionStats = DatastoreV1Stub.ExecutionStats().with {
                $0.resultsReturned = 1
                $0.readOperations = 1
              }
            }
          }
        }
      }
    }

    let client = try DatastoreClient(
      options: DatastoreClientOptions(projectId: "p-agg"),
      stub: stub
    )

    let aggQuery = AggregationQuery(over: Query(kind: "Task"))
      .count(alias: "total", upTo: 500)
      .sum("hours")
      .avg("score")

    let aggRes = try await client.runAggregationQuery(aggQuery)
    #expect(aggRes["total"] == .int64(42))
    #expect(aggRes["sum_hours"] == .int64(120))
    #expect(aggRes["avg_score"] == .double(4.75))
    #expect(aggRes.readTime == readTs)

    let planOnlyAgg = try await client.explainAggregationQuery(aggQuery, analyze: false)
    #expect(planOnlyAgg.results == nil && planOnlyAgg.metrics.executionStats == nil)
    #expect(planOnlyAgg.metrics.planSummary?.indexesUsed.count == 1)

    let analyzedAgg = try await client.explainAggregationQuery(aggQuery, analyze: true)
    #expect(analyzedAgg.results?["total"] == .int64(42))
    #expect(analyzedAgg.metrics.executionStats?.readOperations == 42)

    let planOnlyQuery = try await client.explainQuery(Query(kind: "Task"), analyze: false)
    #expect(planOnlyQuery.entities.isEmpty && planOnlyQuery.metrics.executionStats == nil)
    #expect(planOnlyQuery.metrics.planSummary?.indexesUsed.count == 1)

    let analyzedQuery = try await client.explainQuery(Query(kind: "Task"), analyze: true)
    #expect(
      analyzedQuery.entities.count == 1 && analyzedQuery.endCursor == Cursor(bytes: Data([0x99])))
    #expect(analyzedQuery.metrics.executionStats?.resultsReturned == 1)
  }
}
