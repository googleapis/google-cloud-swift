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
import Testing

@testable import GoogleCloudBigQuery

@Suite struct TableDataTests {
  static let tablePath = "/bigquery/v2/projects/test-project/datasets/d/tables/t"
  static let schemaJSON = #"""
    {"schema": {"fields": [{"name": "name", "type": "STRING"}, {"name": "n", "type": "INT64"}]}}
    """#
  static let schema = Schema([Field("name", .string), Field("n", .int64)])

  // Baseline: U.BigQueryImpl.29, U.TableResult.02, U.Table.02
  @Test func listRowsReadsSchemaThenRows() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.schemaJSON)
    fake.enqueue(
      json: #"""
        {"totalRows": "2", "rows": [{"f": [{"v": "a"}, {"v": "1"}]}, {"f": [{"v": "b"}, {"v": null}]}]}
        """#)
    let rows = try await fake.client().listRows(in: TableID(datasetID: "d", tableID: "t"))

    #expect(rows.schema == Self.schema)
    #expect(rows.totalRows == 2)
    let all = try await rows.collect()
    #expect(all.map { $0["name"] } == [.scalar("a"), .scalar("b")])
    #expect(all.map { $0["N"] } == [.scalar("1"), .null])

    let schemaRequest = fake.requests[0]
    #expect(schemaRequest.method == .get)
    #expect(schemaRequest.path == Self.tablePath)
    #expect(schemaRequest.queryValue("fields") == "schema")
    #expect(schemaRequest.queryValue("view") == "BASIC")
    let dataRequest = fake.requests[1]
    #expect(dataRequest.method == .get)
    #expect(dataRequest.path == "\(Self.tablePath)/data")
    #expect(dataRequest.queryValue("formatOptions.timestampOutputFormat") == "ISO8601_STRING")
    #expect(dataRequest.queryValue("formatOptions.useInt64Timestamp") == nil)
    #expect(dataRequest.queryValue("startIndex") == nil)
    #expect(dataRequest.queryValue("maxResults") == nil)
    #expect(fake.requests.count == 2)
  }

  // Baseline: U.BigQueryImpl.29
  @Test func listRowsWithSchemaInOtherProjectSkipsTablesGet() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    let rows = try await fake.client().listRows(
      in: TableID(projectID: "other", datasetID: "d", tableID: "t"), schema: Self.schema)

    #expect(rows.totalRows == nil)
    #expect(try await rows.collect().isEmpty)
    #expect(fake.requests.map(\.path) == ["/bigquery/v2/projects/other/datasets/d/tables/t/data"])
  }

  // Baseline: U.BigQueryImpl.30
  @Test func listRowsSendsPagingOptions() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"totalRows": "100", "rows": []}"#)
    _ = try await fake.client().listRows(
      in: TableID(datasetID: "d", tableID: "t"), schema: Self.schema, startIndex: 10,
      pageSize: 5, pageToken: "cursor")

    let request = try #require(fake.requests.first)
    #expect(request.queryValue("maxResults") == "5")
    #expect(request.queryValue("pageToken") == "cursor")
    #expect(request.queryValue("startIndex") == "10")
  }

  // Baseline: U.BigQueryImpl.31
  @Test func nextPageUsesTokenWithoutStartIndex() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"{"totalRows": "3", "pageToken": "p2", "rows": [{"f": [{"v": "a"}]}]}"#)
    fake.enqueue(
      json:
        #"{"totalRows": "3", "pageToken": "", "rows": [{"f": [{"v": "b"}]}, {"f": [{"v": "c"}]}]}"#
    )
    let rows = try await fake.client().listRows(
      in: TableID(datasetID: "d", tableID: "t"), schema: Self.schema, selectedFields: ["name"],
      startIndex: 1, pageSize: 2)
    // The first page is fetched eagerly, the next one only on iteration.
    #expect(fake.requests.count == 1)

    let values = try await rows.collect().map { $0["name"] }
    #expect(values == [.scalar("a"), .scalar("b"), .scalar("c")])
    #expect(fake.requests.count == 2)
    let next = fake.requests[1]
    #expect(next.queryValue("pageToken") == "p2")
    #expect(next.queryValue("startIndex") == nil)
    #expect(next.queryValue("maxResults") == "2")
    #expect(next.queryValue("selectedFields") == "name")
    #expect(next.queryValue("formatOptions.timestampOutputFormat") == "ISO8601_STRING")
  }

  // Design: §7(g)
  @Test func selectedFieldsProjectTheGivenSchema() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"{"rows": [{"f": [{"v": "1"}, {"v": {"f": [{"v": "x"}]}}]}]}"#)
    let schema = Schema([
      Field("a", .string),
      Field("n", .int64),
      Field("e", .struct, fields: [Field("d", .string), Field("f", .string)]),
    ])
    let rows = try await fake.client().listRows(
      in: TableID(datasetID: "d", tableID: "t"), schema: schema, selectedFields: ["E.f", "N"])

    // The cells follow the table's column order, not the order of `selectedFields`.
    #expect(
      rows.schema
        == Schema([Field("n", .int64), Field("e", .struct, fields: [Field("f", .string)])]))
    let row = try #require(try await rows.collect().first)
    #expect(row["n"] == .scalar("1"))
    guard case .record(let nested) = row["e"] else {
      Issue.record("expected a record")
      return
    }
    #expect(nested["f"] == .scalar("x"))
    #expect(fake.requests.first?.queryValue("selectedFields") == "E.f,N")
  }

  // Design: §7(g)
  @Test func selectedFieldsAreSentWhenReadingTheSchema() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"schema": {"fields": [{"name": "n", "type": "INT64"}]}}"#)
    fake.enqueue(json: #"{"totalRows": "1", "rows": [{"f": [{"v": "7"}]}]}"#)
    let rows = try await fake.client().listRows(
      in: TableID(datasetID: "d", tableID: "t"), selectedFields: ["n"])

    #expect(rows.schema == Schema([Field("n", .int64)]))
    #expect(try await rows.collect().map { $0["n"] } == [.scalar("7")])
    #expect(fake.requests[0].queryValue("selectedFields") == "n")
    #expect(fake.requests[1].queryValue("selectedFields") == "n")
  }

  // Baseline: U.BigQueryImpl.29
  @Test func listRowsOfMissingTableThrows() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 404, reasons: ["notFound"])
    await #expect {
      _ = try await fake.client().listRows(in: TableID(datasetID: "d", tableID: "t"))
    } throws: { error in
      (error as? BigQueryError)?.isNotFound == true
    }
  }
}
