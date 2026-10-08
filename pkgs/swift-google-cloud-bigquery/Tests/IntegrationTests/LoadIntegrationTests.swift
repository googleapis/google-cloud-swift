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

private let samples = "gs://cloud-samples-data/bigquery"

/// Runs a load job to completion and returns it.
private func runLoad(_ client: BigQueryClient, _ load: LoadJobConfiguration) async throws -> Job {
  let job = try await client.createJob(.load(load))
  return try await client.waitForJob(job.id, timeout: .seconds(300))
}

/// The schema of `table`, read through a query.
private func schema(_ client: BigQueryClient, _ table: TableID) async throws -> [Field] {
  try await client.query("SELECT * FROM \(JobsIT.sql(table)) LIMIT 0").schema?.fields ?? []
}

/// Live tests of load jobs from Cloud Storage.
@Suite(.enabled(if: integrationTestsEnabled()))
struct LoadIntegrationTests {
  // Baseline: IT-144, IT-158
  @Test func csvLoadFromABucket() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
        try await CloudStorage().upload(
          bucket: bucket, name: "load.csv", data: Data("a,1\nb\u{1},2\nc,7\n".utf8),
          contentType: "text/csv")
        let table = JobsIT.table(dataset)
        var load = LoadJobConfiguration(
          destinationTable: table, sourceURIs: ["gs://\(bucket)/load.csv"], format: .csv)
        load.schema = Schema([Field("name", .string), Field("n", .int64)])
        load.csvOptions = CSVOptions(preserveASCIIControlCharacters: true)
        load.rangePartitioning = RangePartitioning(
          field: "n", range: .init(start: 0, end: 10, interval: 5))
        let job = try await runLoad(client, load)
        #expect(job.status.errorResult == nil)
        #expect(job.statistics?.load?.outputRows == 3)
        #expect(job.statistics?.load?.inputFiles == 1)
        guard case .load(let fetched) = job.configuration else {
          Issue.record("expected a load configuration")
          return
        }
        #expect(fetched.rangePartitioning == load.rangePartitioning)
        #expect(fetched.csvOptions?.preserveASCIIControlCharacters == true)
        #expect(
          try await JobsIT.column(
            client, "SELECT name FROM \(JobsIT.sql(table)) ORDER BY n", "name")
            == ["a", "b\u{1}", "c"])
      }
    }
  }

  // Baseline: IT-110
  @Test func loadIntoASessionTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
      try await CloudStorage().upload(
        bucket: bucket, name: "load.json", data: Data(#"{"name": "a"}\#n{"name": "b"}\#n"#.utf8),
        contentType: "application/json")
      let table = TableID(datasetID: "_SESSION", tableID: "swift_session_load")
      var first = LoadJobConfiguration(
        destinationTable: table, sourceURIs: ["gs://\(bucket)/load.json"], format: .json)
      first.schema = Schema([Field("name", .string)])
      first.createDisposition = .createIfNeeded
      first.createSession = true
      let started = try await runLoad(client, first)
      #expect(started.status.errorResult == nil)
      let sessionID = try #require(started.statistics?.sessionInfo?.sessionID)

      var second = first
      second.createSession = nil
      second.connectionProperties = [.sessionID(sessionID)]
      let appended = try await runLoad(client, second)
      #expect(appended.statistics?.sessionInfo?.sessionID == sessionID)

      var read = QueryJobConfiguration("SELECT COUNT(*) AS c FROM _SESSION.swift_session_load")
      read.connectionProperties = [.sessionID(sessionID)]
      let result = try await client.query(read, location: started.id.location)
      #expect(JobsIT.scalars(try await result.rows.collect(), "c") == ["4"])
    }
  }

  // Baseline: IT-145
  @Test func parquetLoadWithDecimalTargetTypes() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = JobsIT.table(dataset)
      var load = LoadJobConfiguration(
        destinationTable: table, sourceURIs: ["\(samples)/numeric/numeric_38_12.parquet"],
        format: .parquet)
      load.decimalTargetTypes = [.numeric, .bigNumeric, .string]
      let job = try await runLoad(client, load)
      guard case .load(let fetched) = job.configuration else {
        Issue.record("expected a load configuration")
        return
      }
      #expect(fetched.decimalTargetTypes == [.numeric, .bigNumeric, .string])
      #expect(try await schema(client, table).first?.type == .bigNumeric)
    }
  }

  // Baseline: IT-159, IT-160
  @Test(arguments: [(DataFormat.avro, "avro"), (DataFormat.parquet, "parquet")])
  func referenceFileSchemaSelectsTheSchema(format: DataFormat, suffix: String) async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = JobsIT.table(dataset)
      let base = "\(samples)/federated-formats-reference-file-schema"
      var load = LoadJobConfiguration(
        destinationTable: table,
        sourceURIs: ["a", "b", "c"].map { "\(base)/\($0)-twitter.\(suffix)" }, format: format)
      load.referenceFileSchemaURI = "\(base)/a-twitter.\(suffix)"
      let job = try await runLoad(client, load)
      #expect(job.status.errorResult == nil)
      #expect(
        try await schema(client, table).map(\.name) == ["username", "tweet", "timestamp", "likes"])
    }
  }

  // Baseline: IT-189
  @Test func flexibleColumnNames() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
        try await CloudStorage().upload(
          bucket: bucket, name: "flexible.csv", data: Data("name,&ampersand\nrow_name,1".utf8),
          contentType: "text/csv")
        for (map, expected) in [(ColumnNameCharacterMap.v1, "_ampersand"), (.v2, "&ampersand")] {
          let table = JobsIT.table(dataset)
          var load = LoadJobConfiguration(
            destinationTable: table, sourceURIs: ["gs://\(bucket)/flexible.csv"], format: .csv)
          load.autodetect = true
          load.columnNameCharacterMap = map
          let job = try await runLoad(client, load)
          #expect(job.status.errorResult == nil)
          #expect(try await schema(client, table).map(\.name) == ["name", expected])
        }
      }
    }
  }
}
