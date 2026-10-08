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

/// Live tests of tables and table data.
@Suite(.enabled(if: integrationTestsEnabled()))
struct TableIntegrationTests {
  static let slice = "tables"
  static let schema = Schema([
    Field("ts", .timestamp, mode: .nullable),
    Field("name", .string, mode: .nullable),
    Field("n", .int64, mode: .nullable),
  ])
  static let jsonRows = """
    {"ts": "2024-01-02 03:04:05", "name": "a", "n": 1}
    {"ts": "2024-01-03 03:04:05", "name": "b", "n": 2}
    """
  static let samples = "gs://cloud-samples-data/bigquery"

  static func tableID(_ dataset: DatasetID, _ suffix: String = "") -> TableID {
    TableID(
      projectID: dataset.projectID, datasetID: dataset.datasetID,
      tableID: "\(suffix)\(IntegrationTest.randomHex())")
  }

  // Baseline: IT-011, IT-026, IT-028, IT-029, IT-030, IT-031, IT-046
  @Test func createGetAndDeleteTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var table = Table(
        id: Self.tableID(dataset, "t_"), schema: Self.schema, description: "d",
        labels: ["k": "v"])
      table.timePartitioning = TimePartitioning(type: .day, field: "ts")
      table.clustering = Clustering(fields: ["name"])
      let created = try await client.createTable(table)
      #expect(created.id == table.id)
      #expect(created.type == .table)
      #expect(created.etag != nil)

      let got = try #require(try await client.getTable(table.id))
      #expect(got.schema?.fields.map(\.name) == ["ts", "name", "n"])
      #expect(got.timePartitioning?.type == .day)
      #expect(got.timePartitioning?.field == "ts")
      #expect(got.clustering == Clustering(fields: ["name"]))
      #expect(got.labels == ["k": "v"])
      #expect(got.description == "d")
      #expect(got.creationTime != nil)
      #expect(got.location != nil)
      #expect(got.numBytes == 0)
      #expect(got.numRows == 0)

      // BASIC omits the storage statistics; the other views include them.
      let basic = try #require(try await client.getTable(table.id, view: .basic))
      #expect(basic.numBytes == nil)
      #expect(basic.numRows == nil)
      for view in [TableMetadataView.full, .storageStats, .unspecified] {
        let withStats = try #require(try await client.getTable(table.id, view: view))
        #expect(withStats.numBytes == 0, "\(view)")
      }

      #expect(try await client.deleteTable(table.id))
      #expect(try await client.getTable(table.id) == nil)
      #expect(try await client.deleteTable(table.id) == false)
    }
  }

  // Baseline: IT-032
  @Test func getTableWithSelectedFields() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      let table = Table(id: Self.tableID(dataset), schema: Self.schema, description: "d")
      _ = try await client.createTable(table, selectedFields: ["etag"])
      let got = try #require(try await client.getTable(table.id, selectedFields: ["creationTime"]))
      #expect(got.id == table.id)
      #expect(got.type == .table)
      #expect(got.creationTime != nil)
      #expect(got.schema == nil)
      #expect(got.description == nil)
      #expect(got.etag == nil)
    }
  }

  // Baseline: IT-023, IT-024
  @Test func defaultCollationAppliesToNewStringFields() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var explicit = Field("explicit", .string)
      explicit.collation = ""
      var table = Table(
        id: Self.tableID(dataset),
        schema: Schema([Field("s", .string), explicit, Field("n", .int64)]))
      table.defaultCollation = "und:ci"
      _ = try await client.createTable(table)

      let got = try #require(try await client.getTable(table.id))
      #expect(got.defaultCollation == "und:ci")
      #expect(got.schema?["s"]?.collation == "und:ci")
      #expect(got.schema?["n"]?.collation == nil)

      var fieldLevel = Field("f", .string)
      fieldLevel.collation = "und:ci"
      let other = Table(id: Self.tableID(dataset), schema: Schema([fieldLevel]))
      _ = try await client.createTable(other)
      let gotOther = try #require(try await client.getTable(other.id))
      #expect(gotOther.defaultCollation == nil)
      #expect(gotOther.schema?["f"]?.collation == "und:ci")
    }
  }

  // Baseline: IT-025
  @Test func createTableWithDefaultValueExpression() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var stringField = Field(
        "s", .string, mode: .nullable, description: "String field with default value expression")
      stringField.defaultValueExpression = "'FOO'"
      stringField.maxLength = 150
      var timestampField = Field(
        "ts", .timestamp, mode: .nullable,
        description: "Timestamp field with default value expression")
      timestampField.defaultValueExpression = "CURRENT_TIMESTAMP"
      let schema = Schema([stringField, timestampField])
      let table = Table(id: Self.tableID(dataset, "default_"), schema: schema)
      _ = try await client.createTable(table)

      let got = try #require(try await client.getTable(table.id))
      #expect(got.schema == schema)
      #expect(got.schema?["s"]?.defaultValueExpression == "'FOO'")
      #expect(got.schema?["s"]?.maxLength == 150)
      #expect(got.schema?["ts"]?.defaultValueExpression == "CURRENT_TIMESTAMP")

      let inserted = try await client.insertAll(
        [
          InsertRow(["ts": "2022-08-22 00:45:12 UTC"], insertID: "rowId1"),
          InsertRow(["ts": "2022-08-23 00:44:33 UTC"], insertID: "rowId2"),
        ],
        into: table.id)
      #expect(inserted.rowErrors.isEmpty)

      let rows = try await client.listRows(in: table.id, schema: schema).collect()
      #expect(rows.count == 2)
      for row in rows {
        #expect(try row["s"]?.stringValue == "FOO")
      }
    }
  }

  // Baseline: IT-012, IT-027, IT-039, IT-040, IT-041
  @Test func listTablesSurfacesPartitioning() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var timePartitioned = Table(id: Self.tableID(dataset, "time_"), schema: Self.schema)
      timePartitioned.timePartitioning = TimePartitioning(
        type: .day, field: "ts", expiration: .seconds(86400))
      var rangePartitioned = Table(id: Self.tableID(dataset, "range_"), schema: Self.schema)
      rangePartitioned.rangePartitioning = RangePartitioning(
        field: "n", range: .init(start: 1, end: 10, interval: 2))
      _ = try await client.createTable(timePartitioned)
      _ = try await client.createTable(rangePartitioned)

      let tables = try await client.listTables(in: dataset, pageSize: 1).collect()
      #expect(Set(tables.map(\.id)) == [timePartitioned.id, rangePartitioned.id])
      let listedTime = try #require(tables.first { $0.id == timePartitioned.id })
      #expect(listedTime.type == .table)
      #expect(listedTime.timePartitioning == timePartitioned.timePartitioning)
      let listedRange = try #require(tables.first { $0.id == rangePartitioned.id })
      #expect(listedRange.rangePartitioning == rangePartitioned.rangePartitioning)
    }
  }

  // Baseline: IT-043, IT-044
  @Test func updateTableSetsAndClearsProperties() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var table = Table(
        id: Self.tableID(dataset), schema: Self.schema, labels: ["a": "1", "b": "2"])
      table.timePartitioning = TimePartitioning(type: .day, field: "ts")
      table.defaultCollation = "und:ci"
      table.defaultRoundingMode = .roundHalfEven
      let created = try await client.createTable(table)
      #expect(created.timePartitioning?.expiration == nil)

      var change = Table(id: table.id, description: "updated", labels: ["c": "3"])
      change.timePartitioning = TimePartitioning(type: .day, expiration: .seconds(42))
      let updated = try await client.updateTable(
        change, clearing: [.label("a")], ifMatch: created.etag)
      #expect(updated.description == "updated")
      #expect(updated.labels == ["b": "2", "c": "3"])
      #expect(updated.timePartitioning?.expiration == .seconds(42))
      #expect(updated.timePartitioning?.field == "ts")
      // Properties the update did not set are unchanged (design §5, proto3 defaults).
      #expect(updated.defaultCollation == "und:ci")
      #expect(updated.defaultRoundingMode == .roundHalfEven)

      let cleared = try await client.updateTable(
        Table(id: table.id), clearing: [.partitionExpiration, .description, .labels])
      #expect(cleared.timePartitioning?.expiration == nil)
      #expect(cleared.timePartitioning?.type == .day)
      #expect(cleared.description == nil)
      #expect(cleared.labels == nil)

      // A stale ETag is rejected.
      await #expect {
        _ = try await client.updateTable(
          Table(id: table.id, description: "stale"), ifMatch: created.etag)
      } throws: { error in
        (error as? BigQueryError)?.httpStatusCode == 412
      }
    }
  }

  // Baseline: IT-045
  @Test func updateNonExistingTableFails() async throws {
    let client = try IntegrationTest.makeClient()
    _ = try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      await #expect {
        _ = try await client.updateTable(Table(id: Self.tableID(dataset), description: "x"))
      } throws: { error in
        guard let error = error as? BigQueryError else { return false }
        return error.isNotFound && error.reason == "notFound"
      }
    }
  }

  // Baseline: IT-036, IT-037
  @Test func createViewAndMaterializedView() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      let base = Table(id: Self.tableID(dataset, "base_"), schema: Self.schema)
      _ = try await client.createTable(base)
      let inserted = try await client.insertAll(
        [
          InsertRow(["ts": "2014-08-19 12:41:35.220000 UTC", "name": "a", "n": 1]),
          InsertRow(["ts": "2014-08-19 12:41:35.220000 UTC", "name": "b", "n": 2]),
        ],
        into: base.id)
      #expect(inserted.rowErrors.isEmpty)
      let baseName = "`\(dataset.projectID!).\(dataset.datasetID).\(base.id.tableID)`"

      var view = Table(id: Self.tableID(dataset, "view_"))
      view.view = ViewDefinition(query: "SELECT name, n FROM \(baseName)")
      let createdView = try await client.createTable(view)
      #expect(createdView.type == .view)
      let gotView = try #require(try await client.getTable(view.id))
      #expect(gotView.view?.query == "SELECT name, n FROM \(baseName)")
      #expect(gotView.view?.useLegacySQL == false)
      #expect(gotView.schema?.fields.map(\.name) == ["name", "n"])

      var viewQuery = QueryJobConfiguration("SELECT * FROM `\(view.id.tableID)` ORDER BY n")
      viewQuery.defaultDataset = dataset
      let viewResult = try await client.query(viewQuery)
      #expect(viewResult.jobID != nil)
      let viewRows = try await viewResult.rows.collect()
      #expect(viewRows.count == 2)
      #expect(try viewRows[0]["name"]?.stringValue == "a")
      #expect(try viewRows[0]["n"]?.int64Value == 1)
      #expect(try viewRows[1]["name"]?.stringValue == "b")
      #expect(try viewRows[1]["n"]?.int64Value == 2)

      var materialized = Table(id: Self.tableID(dataset, "mv_"))
      materialized.materializedView = MaterializedViewDefinition(
        query: "SELECT name, SUM(n) AS total FROM \(baseName) GROUP BY name", enableRefresh: true,
        refreshInterval: .seconds(3600))
      let createdMV = try await client.createTable(materialized)
      #expect(createdMV.type == .materializedView)
      let gotMV = try #require(try await client.getTable(materialized.id))
      #expect(gotMV.materializedView?.enableRefresh == true)
      #expect(gotMV.materializedView?.refreshInterval == .seconds(3600))
    }
  }

  // Baseline: IT-033, IT-185
  @Test func createExternalJSONTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryBucket(slice: Self.slice) { bucket in
      try await CloudStorage().upload(
        bucket: bucket, name: "data.json", data: Data(Self.jsonRows.utf8),
        contentType: "application/json")
      try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
        var table = Table(id: Self.tableID(dataset, "ext_"))
        var external = ExternalDataConfiguration(
          sourceURIs: ["gs://\(bucket)/data.json"], format: .json, schema: Self.schema)
        external.ignoreUnknownValues = true
        external.maxBadRecords = 3
        table.externalDataConfiguration = external
        let created = try await client.createTable(table)
        #expect(created.type == .external)

        let got = try #require(try await client.getTable(table.id))
        #expect(got.schema?.fields.map(\.name) == ["ts", "name", "n"])
        let config = try #require(got.externalDataConfiguration)
        #expect(config.sourceURIs == ["gs://\(bucket)/data.json"])
        #expect(config.format == .json)
        #expect(config.ignoreUnknownValues == true)
        #expect(config.maxBadRecords == 3)
        #expect(config.metadataCacheMode == nil)

        let job = try await client.createJob(
          .query(
            QueryJobConfiguration(
              "SELECT * FROM `\(dataset.projectID!).\(dataset.datasetID).\(table.id.tableID)`")))
        let finished = try await client.waitForJob(job.id)
        #expect(finished.status.errorResult == nil)
        let queryJob = try #require(try await client.getJob(job.id))
        let usage = try #require(
          queryJob.statistics?.query?.metadataCacheStatistics?.tableMetadataCacheUsage)
        #expect(usage.count == 1)
        #expect(usage.first?.unusedReason == .metadataCachingNotEnabled)
      }
    }
  }

  // Baseline: IT-035
  @Test func updateExternalTableWithAutodetectSchema() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryBucket(slice: Self.slice) { bucket in
      try await CloudStorage().upload(
        bucket: bucket, name: "data.json", data: Data(Self.jsonRows.utf8),
        contentType: "application/json")
      try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
        var table = Table(id: Self.tableID(dataset, "ext_"))
        table.externalDataConfiguration = ExternalDataConfiguration(
          sourceURIs: ["gs://\(bucket)/data.json"], format: .json,
          schema: Schema([Field("name", .string)]))
        _ = try await client.createTable(table)

        var change = Table(id: table.id)
        var external = ExternalDataConfiguration(
          sourceURIs: ["gs://\(bucket)/data.json"], format: .json)
        external.autodetect = true
        change.externalDataConfiguration = external
        let updated = try await client.updateTable(change, autodetectSchema: true)
        #expect(Set(updated.schema?.fields.map(\.name) ?? []) == ["ts", "name", "n"])
      }
    }
  }

  // Baseline: IT-186
  @Test func metadataCacheModeIsRejectedForNonBigLakeTables() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var table = Table(id: Self.tableID(dataset, "ext_"))
      var external = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/us-states/us-states.csv"], format: .csv,
        schema: Schema([Field("name", .string), Field("post_abbr", .string)]))
      external.metadataCacheMode = .automatic
      table.externalDataConfiguration = external
      await #expect {
        _ = try await client.createTable(table)
      } throws: { error in
        guard let error = error as? BigQueryError else { return false }
        return error.reason == "invalid"
          && error.message.contains("metadataCacheMode provided for non BigLake external table")
      }
    }
  }

  // Baseline: IT-146
  @Test func externalParquetTableWithDecimalTargetTypes() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var table = Table(id: Self.tableID(dataset, "parquet_"))
      var external = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/numeric/numeric_38_12.parquet"], format: .parquet)
      external.decimalTargetTypes = [.numeric, .bigNumeric, .string]
      table.externalDataConfiguration = external
      _ = try await client.createTable(table)
      let got = try #require(try await client.getTable(table.id))
      #expect(got.schema?.fields.first?.type == .bigNumeric)
      #expect(
        got.externalDataConfiguration?.decimalTargetTypes == [.numeric, .bigNumeric, .string])
    }
  }

  // Baseline: IT-161, IT-162
  @Test(arguments: [DataFormat.avro, .parquet])
  func externalTableWithReferenceFileSchema(format: DataFormat) async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      let ext = format == .avro ? "avro" : "parquet"
      let prefix = "\(Self.samples)/federated-formats-reference-file-schema"
      var table = Table(id: Self.tableID(dataset, "\(ext)_"))
      var external = ExternalDataConfiguration(sourceURIs: ["\(prefix)/*.\(ext)"], format: format)
      external.referenceFileSchemaURI = "\(prefix)/a-twitter.\(ext)"
      table.externalDataConfiguration = external
      _ = try await client.createTable(table)
      let got = try #require(try await client.getTable(table.id))
      // The table takes the schema of the reference file, a-twitter.
      #expect(got.schema?.fields.map(\.name) == ["username", "tweet", "timestamp", "likes"])
      #expect(got.externalDataConfiguration?.referenceFileSchemaURI == "\(prefix)/a-twitter.\(ext)")
    }
  }

  // Baseline: IT-164
  @Test func hivePartitioningFieldsArePopulated() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryBucket(slice: Self.slice) { bucket in
      try await CloudStorage().upload(
        bucket: bucket, name: "hive/key=foo/data.json", data: Data(#"{"name":"bar"}"#.utf8),
        contentType: "application/json")
      try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
        var table = Table(id: Self.tableID(dataset, "hive_"))
        var external = ExternalDataConfiguration(
          sourceURIs: ["gs://\(bucket)/hive/*"], format: .json)
        external.autodetect = true
        var hive = HivePartitioningOptions()
        hive.mode = "AUTO"
        hive.requirePartitionFilter = true
        hive.sourceURIPrefix = "gs://\(bucket)/hive/"
        external.hivePartitioningOptions = hive
        table.externalDataConfiguration = external
        _ = try await client.createTable(table)

        let got = try #require(try await client.getTable(table.id))
        #expect(got.externalDataConfiguration?.hivePartitioningOptions?.fields == ["key"])
        #expect(
          got.externalDataConfiguration?.hivePartitioningOptions?.requirePartitionFilter == true)
      }
    }
  }

  // Baseline: IT-076, IT-077
  @Test func queryExternalHivePartitioningAutoAndCustomLayout() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice, location: "US") {
      dataset in
      let parquet = ParquetOptions(enableListInference: true, enumAsString: true)

      var autoTable = Table(id: Self.tableID(dataset, "hive_auto_"))
      var autoExternal = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/hive-partitioning-samples/autolayout/*"], format: .parquet)
      autoExternal.autodetect = true
      autoExternal.parquetOptions = parquet
      autoExternal.hivePartitioningOptions = HivePartitioningOptions(
        mode: "AUTO",
        sourceURIPrefix: "\(Self.samples)/hive-partitioning-samples/autolayout/",
        requirePartitionFilter: true)
      autoTable.externalDataConfiguration = autoExternal
      _ = try await client.createTable(autoTable)

      var autoQuery = QueryJobConfiguration(
        "SELECT COUNT(*) AS ct FROM `\(autoTable.id.tableID)` WHERE dt = \"2020-11-15\"")
      autoQuery.defaultDataset = dataset
      let autoResult = try await client.query(autoQuery)
      #expect(autoResult.jobID != nil)
      #expect(autoResult.totalRows == 1)
      let autoRows = try await autoResult.rows.collect()
      #expect(try autoRows.first?["ct"]?.int64Value == 50)

      var customTable = Table(id: Self.tableID(dataset, "hive_custom_"))
      var customExternal = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/hive-partitioning-samples/customlayout/*"], format: .parquet)
      customExternal.autodetect = true
      customExternal.parquetOptions = parquet
      customExternal.hivePartitioningOptions = HivePartitioningOptions(
        mode: "CUSTOM",
        sourceURIPrefix:
          "\(Self.samples)/hive-partitioning-samples/customlayout/{pkey:STRING}/",
        requirePartitionFilter: true)
      customTable.externalDataConfiguration = customExternal
      _ = try await client.createTable(customTable)

      var customQuery = QueryJobConfiguration(
        "SELECT COUNT(*) AS ct FROM `\(customTable.id.tableID)` WHERE pkey = \"foo\"")
      customQuery.defaultDataset = dataset
      let customResult = try await client.query(customQuery)
      #expect(customResult.jobID != nil)
      #expect(customResult.totalRows == 1)
      let customRows = try await customResult.rows.collect()
      #expect(try customRows.first?["ct"]?.int64Value == 50)
    }
  }

  // Baseline: IT-016, IT-165, IT-166, IT-167, IT-168
  @Test func primaryAndForeignKeys() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      let keySchema = Schema([Field("id", .int64), Field("other", .int64), Field("x", .string)])
      var parent = Table(id: Self.tableID(dataset, "parent_"), schema: keySchema)
      parent.tableConstraints = TableConstraints(primaryKey: PrimaryKey(columns: ["id"]))
      let createdParent = try await client.createTable(parent)
      #expect(createdParent.tableConstraints?.primaryKey == PrimaryKey(columns: ["id"]))

      // Add a primary key with an update.
      let second = Table(id: Self.tableID(dataset, "second_"), schema: keySchema)
      _ = try await client.createTable(second)
      var addKey = Table(id: second.id)
      addKey.tableConstraints = TableConstraints(primaryKey: PrimaryKey(columns: ["id", "other"]))
      let updatedSecond = try await client.updateTable(addKey)
      #expect(updatedSecond.tableConstraints?.primaryKey == PrimaryKey(columns: ["id", "other"]))

      // Create a table with a foreign key; the referenced project defaults to the client's.
      let parentReference = TableID(datasetID: dataset.datasetID, tableID: parent.id.tableID)
      var child = Table(id: Self.tableID(dataset, "child_"), schema: keySchema)
      let toParent = ForeignKey(
        name: "fk_parent", referencedTable: parentReference,
        columnReferences: [ColumnReference(referencingColumn: "other", referencedColumn: "id")])
      child.tableConstraints = TableConstraints(foreignKeys: [toParent])
      let createdChild = try await client.createTable(child)
      let createdKey = try #require(createdChild.tableConstraints?.foreignKeys.first)
      #expect(createdKey.name == "fk_parent")
      #expect(createdKey.referencedTable == parent.id)
      #expect(createdKey.columnReferences == toParent.columnReferences)

      // Replace the foreign keys with an update.
      let toSecond = ForeignKey(
        name: "fk_second", referencedTable: second.id,
        columnReferences: [
          ColumnReference(referencingColumn: "id", referencedColumn: "id"),
          ColumnReference(referencingColumn: "other", referencedColumn: "other"),
        ])
      var replace = Table(id: child.id)
      replace.tableConstraints = TableConstraints(
        primaryKey: PrimaryKey(columns: ["id"]), foreignKeys: [toParent, toSecond])
      let updatedChild = try await client.updateTable(replace)
      #expect(updatedChild.tableConstraints?.foreignKeys.map(\.name) == ["fk_parent", "fk_second"])
      #expect(updatedChild.tableConstraints?.primaryKey == PrimaryKey(columns: ["id"]))

      // Remove all constraints.
      let removed = try await client.updateTable(Table(id: child.id), clearing: [.tableConstraints])
      #expect(removed.tableConstraints == nil)
    }
  }

  // Baseline: IT-042
  @Test func listPartitionsOfPublicTable() async throws {
    let client = try IntegrationTest.makeClient()
    let partitions = try await client.listPartitions(
      of: TableID(
        projectID: "bigquery-public-data", datasetID: "google_trends", tableID: "top_terms"))
    #expect(!partitions.isEmpty)
    #expect(partitions.allSatisfy { $0.count == 8 && $0.allSatisfy(\.isNumber) })

    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      var table = Table(id: Self.tableID(dataset, "part_"), schema: Self.schema)
      table.timePartitioning = TimePartitioning(type: .day, field: "ts")
      _ = try await client.createTable(table)

      _ = try await client.query(
        "INSERT INTO `\(dataset.projectID!).\(dataset.datasetID).\(table.id.tableID)` (ts, name) VALUES ('2024-01-02 03:04:05 UTC', 'v')"
      )

      let tablePartitions = try await client.listPartitions(of: table.id)
      #expect(tablePartitions == ["20240102"])
    }
  }

  // Baseline: IT-051
  @Test func listAllTableDataAcrossFieldTypes() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice) { dataset in
      let recordSubfields = [
        Field("TimestampField", .timestamp),
        Field("StringField", .string),
        Field("IntegerArrayField", .int64, mode: .repeated),
        Field("BooleanField", .bool),
      ]
      let allTypesSchema = Schema([
        Field("TimestampField", .timestamp),
        Field("StringField", .string),
        Field("IntegerArrayField", .int64, mode: .repeated),
        Field("BooleanField", .bool),
        Field("BytesField", .bytes),
        Field("RecordField", .struct, fields: recordSubfields),
        Field("IntegerField", .int64),
        Field("FloatField", .float64),
        Field("GeographyField", .geography),
        Field("NumericField", .numeric),
      ])
      let table = Table(id: Self.tableID(dataset, "all_types_"), schema: allTypesSchema)
      _ = try await client.createTable(table)

      let rowToInsert = InsertRow([
        "TimestampField": "2014-08-19 12:41:35.220000 UTC",
        "StringField": "stringValue",
        "IntegerArrayField": [0, 1],
        "BooleanField": false,
        "BytesField": .bytes(Data([1, 2, 3])),
        "RecordField": [
          "TimestampField": "1969-07-20 20:18:04.000000 UTC",
          "StringField": nil,
          "IntegerArrayField": [1, 0],
          "BooleanField": true,
        ],
        "IntegerField": 3,
        "FloatField": 1.2,
        "GeographyField": "POINT(-122.35022 47.649154)",
        "NumericField": .numeric(Decimal(string: "123456.789012345")!),
      ])
      let inserted = try await client.insertAll([rowToInsert, rowToInsert], into: table.id)
      #expect(inserted.rowErrors.isEmpty)

      let rows = try await client.listRows(in: table.id).collect()
      #expect(rows.count == 2)
      for row in rows {
        #expect(try row["TimestampField"]?.timestampMicros == 1_408_452_095_220_000)
        #expect(try row["StringField"]?.stringValue == "stringValue")
        #expect(try row["IntegerArrayField"]?.arrayValue?.map { try $0.int64Value } == [0, 1])
        #expect(try row["BooleanField"]?.boolValue == false)
        #expect(try row["BytesField"]?.bytesValue == Data([1, 2, 3]))
        let record = try #require(try row["RecordField"]?.recordValue)
        #expect(try record["TimestampField"]?.timestampMicros == -14_182_916_000_000)
        #expect(record["StringField"]?.isNull == true)
        #expect(try record["IntegerArrayField"]?.arrayValue?.map { try $0.int64Value } == [1, 0])
        #expect(try record["BooleanField"]?.boolValue == true)
        #expect(try row["IntegerField"]?.int64Value == 3)
        #expect(try row["FloatField"]?.doubleValue == 1.2)
        #expect(try row["GeographyField"]?.geographyValue == "POINT(-122.35022 47.649154)")
        #expect(try row["NumericField"]?.numericValue == Decimal(string: "123456.789012345"))
      }
    }
  }

  // Baseline: IT-052
  @Test func listRowsOfPublicTableWithStartIndex() async throws {
    let client = try IntegrationTest.makeClient()
    let table = TableID(
      projectID: "bigquery-public-data", datasetID: "census_bureau_international",
      tableID: "midyear_population_agespecific")
    let numRows = try #require(try await client.getTable(table)?.numRows)

    // Start 5 rows before the end and read them in pages of 3.
    let rows = try await client.listRows(in: table, startIndex: numRows - 5, pageSize: 3)
    #expect(rows.totalRows == numRows)
    var pages = rows.pages.makeAsyncIterator()
    let first = try #require(try await pages.next())
    #expect(first.items.count == 3)
    #expect(first.nextPageToken != nil)
    #expect(first.items.first?["country_name"] != nil)
    let second = try #require(try await pages.next())
    #expect(second.items.count == 2)
    #expect(second.nextPageToken == nil)
    #expect(try await pages.next() == nil)

    // Selected columns come back in table order.
    let selected = try await client.listRows(
      in: table, selectedFields: ["year", "country_code"], startIndex: 2, pageSize: 2)
    #expect(selected.schema.fields.map(\.name) == ["country_code", "year"])
    var selectedPages = selected.pages.makeAsyncIterator()
    let row = try #require(try await selectedPages.next()?.items.first)
    #expect(row.values.count == 2)
  }

  /// The BigQuery connection for BigLake and object tables, `{location}.{connection}`, from
  /// `BIGQUERY_TEST_CONNECTION_ID`.
  static var connection: String? {
    ProcessInfo.processInfo.environment["BIGQUERY_TEST_CONNECTION_ID"].flatMap {
      $0.isEmpty ? nil : $0
    }
  }

  // Baseline: IT-034
  @Test(.enabled(if: connection != nil))
  func createExternalTableWithConnectionAndSchema() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice, location: "US") {
      dataset in
      let connection = "\(client.projectID).\(Self.connection!)"
      var table = Table(id: Self.tableID(dataset, "biglake_"))
      var external = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/us-states/us-states.json"], format: .json,
        schema: Schema([Field("name", .string), Field("post_abbr", .string)]))
      external.connectionID = connection
      table.externalDataConfiguration = external
      let created = try await client.createTable(table)
      #expect(created.id == table.id)

      let got = try #require(try await client.getTable(table.id))
      #expect(got.schema?.fields.map(\.name) == ["name", "post_abbr"])
      #expect(got.externalDataConfiguration?.connectionID != nil)
      #expect(try await client.deleteTable(table.id))
    }
  }

  // Baseline: IT-187
  @Test(.enabled(if: connection != nil))
  func createObjectTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: Self.slice, location: "US") {
      dataset in
      var table = Table(id: Self.tableID(dataset, "objects_"))
      var external = ExternalDataConfiguration(
        sourceURIs: ["\(Self.samples)/us-states/*"], format: nil)
      external.connectionID = "\(client.projectID).\(Self.connection!)"
      external.objectMetadata = .simple
      table.externalDataConfiguration = external
      _ = try await client.createTable(table)

      let got = try #require(try await client.getTable(table.id))
      #expect(got.externalDataConfiguration?.objectMetadata == .simple)
      #expect(got.schema?["uri"] != nil)

      let job = try await client.createJob(
        .query(
          QueryJobConfiguration(
            "SELECT * FROM `\(dataset.projectID!).\(dataset.datasetID).\(table.id.tableID)`")))
      let finished = try await client.waitForJob(job.id)
      #expect(finished.status.errorResult == nil)
      let queryJob = try #require(try await client.getJob(job.id))
      #expect((queryJob.statistics?.query?.totalBytesProcessed ?? 0) > 0)
    }
  }
}
