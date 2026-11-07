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

import Foundation
import GoogleWKT
import Testing

@testable import GoogleCloudDatastore

@Suite struct ClientAPISurfaceTests {
  @Test func cursorUrlSafeRoundTrip() throws {
    let raw = Data([0xFF, 0xFE, 0x3E, 0x3F, 0x00, 0x01])
    let cursor = Cursor(bytes: raw)
    let encoded = cursor.toUrlSafe()
    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    #expect(!encoded.contains("="))

    let decoded = try Cursor(urlSafe: encoded)
    #expect(decoded == cursor)
  }

  @Test func structuredQueryFluentBuilder() {
    let ancestor = Key(kind: "Project", name: "apollo")
    let startCursor = Cursor(bytes: Data([1, 2]))
    let endCursor = Cursor(bytes: Data([3, 4]))

    let query = Query(kind: "Task", namespaceId: "prod")
      .hasAncestor(ancestor)
      .filter(.equal("done", false))
      .filter(.or([.greaterThanOrEqual("priority", 3), .in("tag", ["urgent", "blocker"])]))
      .project(["title", "priority"])
      .distinctOn(["priority"])
      .order(by: "priority", direction: .descending)
      .order(by: "created")
      .start(at: startCursor)
      .end(at: endCursor)
      .offset(10)
      .limit(25)

    #expect(query.kind == "Task")
    #expect(query.namespaceId == "prod")
    #expect(query.projection == ["title", "priority"])
    #expect(query.distinctOn == ["priority"])
    #expect(query.order == [.descending("priority"), .ascending("created")])
    #expect(query.startCursor == startCursor)
    #expect(query.endCursor == endCursor)
    #expect(query.offset == 10)
    #expect(query.limit == 25)
    #expect(query.keysOnly().projection == ["__key__"])
  }

  @Test func gqlAndAggregationQueryBuilders() {
    let gql = GqlQuery(
      "SELECT * FROM Task WHERE done = @done AND priority > @1",
      allowLiterals: false,
      namedBindings: ["done": .value(false)],
      positionalBindings: [.value(2)],
      namespaceId: "ns"
    )
    #expect(gql.queryString.contains("SELECT * FROM Task"))
    #expect(gql.namedBindings["done"] == .value(.bool(false)))
    #expect(gql.positionalBindings == [.value(.int64(2))])

    let agg = AggregationQuery(over: Query(kind: "Task"))
      .count(alias: "total", upTo: 1_000)
      .sum("hours")
      .avg("score", alias: "mean_score")

    #expect(agg.aggregations.count == 3)
    #expect(agg.aggregations[0].alias == "total")
    #expect(agg.aggregations[1].alias == "sum_hours")
    #expect(agg.aggregations[2].alias == "mean_score")

    let results = AggregationResults(values: ["total": 42, "mean_score": 4.5])
    #expect(results["total"] == .int64(42))
    #expect(results["mean_score"] == .double(4.5))
  }
}
