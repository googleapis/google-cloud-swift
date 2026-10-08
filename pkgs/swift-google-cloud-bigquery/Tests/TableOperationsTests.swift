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
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

@Suite struct TableOperationsTests {
  static let tablesPath = "/bigquery/v2/projects/test-project/datasets/d/tables"
  static let tablePath = "\(tablesPath)/t"
  static let tableJSON = #"""
    {"tableReference": {"projectId": "test-project", "datasetId": "d", "tableId": "t"},
     "type": "TABLE", "etag": "e1"}
    """#

  // Baseline: U.BigQueryImpl.12, U.Table.02
  @Test func createTablePostsWithClientProject() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    let table = Table(
      id: TableID(datasetID: "d", tableID: "t"), schema: Schema([Field("a", .string)]))
    let created = try await fake.client().createTable(table)

    #expect(created.id == TableID(projectID: "test-project", datasetID: "d", tableID: "t"))
    #expect(created.etag == "e1")
    let request = try #require(fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == Self.tablesPath)
    #expect(request.queryValue("fields") == nil)
    let body = try request.jsonBody()
    let reference = try #require(body["tableReference"] as? [String: Any])
    #expect(reference["projectId"] as? String == "test-project")
    #expect(reference["tableId"] as? String == "t")
    #expect(body["schema"] != nil)
  }

  // Baseline: U.BigQueryImpl.12
  @Test func createExternalTableSendsSchemaAtTableLevel() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    var external = ExternalDataConfiguration(
      sourceURIs: ["gs://b/a.csv"], format: .csv, schema: Schema([Field("a", .string)]))
    external.csvOptions = CSVOptions()
    var table = Table(id: TableID(projectID: "other", datasetID: "d", tableID: "t"))
    table.externalDataConfiguration = external
    _ = try await fake.client().createTable(table)

    let request = try #require(fake.requests.first)
    #expect(request.path == "/bigquery/v2/projects/other/datasets/d/tables")
    let body = try request.jsonBody()
    #expect(body["schema"] != nil)
    let sent = try #require(body["externalDataConfiguration"] as? [String: Any])
    #expect(sent["schema"] == nil)
    #expect(sent["sourceFormat"] as? String == "CSV")
  }

  // Baseline: U.BigQueryImpl.12
  @Test func createTableIsNotRetried() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, reasons: ["backendError"])
    await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().createTable(Table(id: TableID(datasetID: "d", tableID: "t")))
    }
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryImpl.13
  @Test func selectedFieldsAlwaysIncludeRequiredFields() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    fake.enqueue(json: Self.tableJSON)
    fake.enqueue(json: Self.tableJSON)
    let client = fake.client()
    let id = TableID(datasetID: "d", tableID: "t")
    _ = try await client.createTable(Table(id: id), selectedFields: ["schema", "etag"])
    _ = try await client.getTable(id, selectedFields: ["schema", "etag", "type"])
    _ = try await client.updateTable(Table(id: id), selectedFields: ["etag"])

    let fields = fake.requests.map { $0.queryValue("fields") }
    #expect(
      fields == [
        "tableReference,type,schema,etag", "tableReference,type,schema,etag",
        "tableReference,type,etag",
      ])
  }

  // Baseline: U.BigQueryImpl.14, U.Table.02
  @Test func getTableUsesStorageStatsViewByDefault() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    fake.enqueue(json: Self.tableJSON)
    let client = fake.client()
    let table = try await client.getTable(TableID(datasetID: "d", tableID: "t"))
    _ = try await client.getTable(
      TableID(projectID: "other", datasetID: "d", tableID: "t"), view: .full)

    #expect(table?.etag == "e1")
    #expect(fake.requests[0].method == .get)
    #expect(fake.requests[0].path == Self.tablePath)
    #expect(fake.requests[0].queryValue("view") == "STORAGE_STATS")
    #expect(fake.requests[1].path == "/bigquery/v2/projects/other/datasets/d/tables/t")
    #expect(fake.requests[1].queryValue("view") == "FULL")
  }

  // Baseline: U.BigQueryImpl.06
  @Test func getMissingTableReturnsNil() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 404, reasons: ["notFound"])
    #expect(try await fake.client().getTable(TableID(datasetID: "d", tableID: "t")) == nil)
  }

  // Baseline: U.BigQueryImpl.15
  @Test func getTableRetriesBackendError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, reasons: ["backendError"])
    fake.enqueue(json: Self.tableJSON)
    let table = try await fake.client().getTable(TableID(datasetID: "d", tableID: "t"))
    #expect(table != nil)
    #expect(fake.requests.count == 2)
  }

  // Baseline: U.BigQueryImpl.16
  @Test func getTableWithRefusingRetryPolicyMakesOneAttempt() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, reasons: ["backendError"])
    fake.enqueue(json: Self.tableJSON)
    let client = fake.client(retryPolicy: BigQueryRetryPolicy.unbounded().withAttemptLimit(1))
    await #expect(throws: BigQueryError.self) {
      _ = try await client.getTable(TableID(datasetID: "d", tableID: "t"))
    }
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryImpl.17, U.Table.02
  @Test func listTablesFollowsPageTokens() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"""
        {"nextPageToken": "next", "tables": [{"tableReference": {"projectId": "test-project",
          "datasetId": "d", "tableId": "a"}, "type": "TABLE"}]}
        """#)
    fake.enqueue(
      json: #"""
        {"tables": [{"tableReference": {"projectId": "test-project", "datasetId": "d",
          "tableId": "b"}, "type": "VIEW"}]}
        """#)
    let tables = try await fake.client().listTables(
      in: DatasetID(datasetID: "d"), pageSize: 1, pageToken: "start"
    ).collect()

    #expect(tables.map(\.id.tableID) == ["a", "b"])
    #expect(tables.map(\.type) == [.table, .view])
    #expect(fake.requests.map(\.path) == [Self.tablesPath, Self.tablesPath])
    #expect(fake.requests.map { $0.queryValue("maxResults") } == ["1", "1"])
    #expect(fake.requests.map { $0.queryValue("pageToken") } == ["start", "next"])
  }

  // Baseline: U.BigQueryImpl.17
  @Test func listTablesInOtherProject() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: "{}")
    let tables = try await fake.client().listTables(
      in: DatasetID(projectID: "other", datasetID: "d")
    ).collect()
    #expect(tables.isEmpty)
    #expect(fake.requests.first?.path == "/bigquery/v2/projects/other/datasets/d/tables")
    #expect(fake.requests.first?.queryValue("maxResults") == nil)
  }

  // Baseline: U.BigQueryImpl.18
  @Test func listTablesKeepsPartitioningAndLabels() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"""
        {"tables": [
          {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "a"},
           "timePartitioning": {"type": "DAY", "expirationMs": "86400000"}, "id": "p:d.a",
           "friendlyName": "A", "creationTime": "1546275600000", "expirationTime": "1700000000000",
           "clustering": {"fields": ["c"]}, "requirePartitionFilter": true},
          {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "b"},
           "timePartitioning": {"field": "timestampField"}},
          {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "c"},
           "rangePartitioning": {"field": "n", "range": {"start": "1", "end": "10",
             "interval": "2"}}},
          {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "e"},
           "labels": {"key": "value"}}]}
        """#)
    let tables = try await fake.client().listTables(in: DatasetID(datasetID: "d")).collect()

    #expect(tables[0].timePartitioning == TimePartitioning(type: .day, expiration: .seconds(86400)))
    #expect(tables[0].generatedID == "p:d.a")
    #expect(tables[0].friendlyName == "A")
    #expect(tables[0].creationTime == Date(timeIntervalSince1970: 1_546_275_600))
    #expect(tables[0].expirationTime == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(tables[0].clustering == Clustering(fields: ["c"]))
    #expect(tables[0].requirePartitionFilter == true)
    // A missing partitioning type means DAY, as in Java.
    #expect(tables[1].timePartitioning == TimePartitioning(type: .day, field: "timestampField"))
    #expect(
      tables[2].rangePartitioning
        == RangePartitioning(field: "n", range: .init(start: 1, end: 10, interval: 2)))
    #expect(tables[3].labels == ["key": "value"])
  }

  // Baseline: U.BigQueryImpl.19
  @Test func listPartitionsReadsPartitionsSummary() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"""
        {"schema": {"fields": [{"name": "project_id", "type": "STRING"},
          {"name": "partition_id", "type": "STRING"}]}}
        """#)
    fake.enqueue(
      json: #"""
        {"totalRows": "2", "rows": [{"f": [{"v": "p"}, {"v": "20240101"}]},
          {"f": [{"v": "p"}, {"v": "20240102"}]}]}
        """#)
    let partitions = try await fake.client().listPartitions(
      of: TableID(datasetID: "d", tableID: "t"))

    #expect(partitions == ["20240101", "20240102"])
    let summary = "\(Self.tablesPath)/t%24__PARTITIONS_SUMMARY__"
    #expect(fake.requests.map(\.path) == [summary, "\(summary)/data"])
  }

  // Baseline: U.BigQueryImpl.20, U.Table.02
  @Test func deleteTableReturnsWhetherItExisted() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 204, json: "")
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let client = fake.client()
    #expect(try await client.deleteTable(TableID(datasetID: "d", tableID: "t")))
    #expect(
      try await client.deleteTable(TableID(projectID: "other", datasetID: "d", tableID: "t"))
        == false)
    #expect(fake.requests.map(\.method) == [.delete, .delete])
    #expect(
      fake.requests.map(\.path) == [
        Self.tablePath, "/bigquery/v2/projects/other/datasets/d/tables/t",
      ])
  }

  // Baseline: U.BigQueryImpl.21, U.Table.02
  @Test func updateTablePatchesWithClientProject() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    var table = Table(id: TableID(datasetID: "d", tableID: "t"), description: "new")
    table.etag = "ignored"
    let updated = try await fake.client().updateTable(table)

    #expect(updated.etag == "e1")
    let request = try #require(fake.requests.first)
    #expect(request.method == .patch)
    #expect(request.path == Self.tablePath)
    #expect(request.headers["If-Match"] == nil)
    #expect(request.queryValue("autodetect_schema") == nil)
    let body = try request.jsonBody()
    #expect(body["description"] as? String == "new")
    #expect(body["etag"] == nil)
    #expect((body["tableReference"] as? [String: Any])?["projectId"] as? String == "test-project")
  }

  // Baseline: U.BigQueryImpl.21
  @Test func updateTableRetriesOnlyWithETag() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503, reasons: ["backendError"])
    fake.enqueueError(status: 503, reasons: ["backendError"])
    fake.enqueue(json: Self.tableJSON)
    let client = fake.client()
    let table = Table(id: TableID(datasetID: "d", tableID: "t"))
    await #expect(throws: BigQueryError.self) { _ = try await client.updateTable(table) }
    #expect(fake.requests.count == 1)

    _ = try await client.updateTable(table, ifMatch: "e1")
    #expect(fake.requests.count == 3)
    #expect(fake.requests[2].headers["If-Match"] == "e1")
  }

  // Baseline: U.BigQueryImpl.22
  @Test func updateExternalTableSendsSchemaAtTableLevel() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    var table = Table(id: TableID(datasetID: "d", tableID: "t"))
    table.externalDataConfiguration = ExternalDataConfiguration(
      sourceURIs: ["gs://b/a.csv"], format: .csv, schema: Schema([Field("a", .string)]))
    _ = try await fake.client().updateTable(table)

    let body = try #require(fake.requests.first).jsonBody()
    let schema = try #require(body["schema"] as? [String: Any])
    #expect((schema["fields"] as? [[String: Any]])?.first?["name"] as? String == "a")
    #expect((body["externalDataConfiguration"] as? [String: Any])?["schema"] == nil)
  }

  // Baseline: U.BigQueryImpl.23
  @Test func updateTableWithAutodetectSchema() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    _ = try await fake.client().updateTable(
      Table(id: TableID(datasetID: "d", tableID: "t")), autodetectSchema: true)
    #expect(fake.requests.first?.queryValue("autodetect_schema") == "true")
  }

  // Design: §4 (Table.Field)
  @Test func updateTableSendsNullForClearedFields() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    var table = Table(id: TableID(datasetID: "d", tableID: "t"), labels: ["keep": "v"])
    table.timePartitioning = TimePartitioning(type: .day)
    _ = try await fake.client().updateTable(
      table, clearing: [.label("drop"), .partitionExpiration, .description])

    let body = try #require(fake.requests.first).jsonBody()
    let labels = try #require(body["labels"] as? [String: Any])
    #expect(labels["keep"] as? String == "v")
    #expect(labels["drop"] is NSNull)
    let partitioning = try #require(body["timePartitioning"] as? [String: Any])
    #expect(partitioning["type"] as? String == "DAY")
    #expect(partitioning["expirationMs"] is NSNull)
    #expect(body["description"] is NSNull)
  }

  // Baseline: U.HttpBigQueryRpc.03
  @Test(arguments: [
    ("create", HTTPMethod.post, tablesPath),
    ("get", .get, tablePath),
    ("list", .get, tablesPath),
    ("update", .patch, tablePath),
    ("delete", .delete, tablePath),
    ("listRows", .get, "\(tablePath)/data"),
  ])
  func routes(operation: String, method: HTTPMethod, path: String) async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: Self.tableJSON)
    let client = fake.client()
    let id = TableID(datasetID: "d", tableID: "t")
    switch operation {
    case "create": _ = try await client.createTable(Table(id: id))
    case "get": _ = try await client.getTable(id)
    case "list": _ = try await client.listTables(in: id.dataset).collect()
    case "update": _ = try await client.updateTable(Table(id: id))
    case "delete": _ = try await client.deleteTable(id)
    default: _ = try await client.listRows(in: id, schema: Schema([]))
    }
    #expect(fake.requests.first?.method == method)
    #expect(fake.requests.first?.path == path)
  }
}
