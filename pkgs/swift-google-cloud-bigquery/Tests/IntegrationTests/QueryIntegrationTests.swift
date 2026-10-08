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

/// Live tests of `query()`, its fast and slow paths, and query results.
@Suite(.enabled(if: integrationTestsEnabled()))
struct QueryIntegrationTests {
  // Baseline: IT-067, IT-098, IT-099, IT-100
  @Test func fastQueryReturnsRowsAndDistinctJobs() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let sql = "SELECT name, n FROM \(JobsIT.sql(table)) ORDER BY n"
      let first = try await client.query(sql)
      let second = try await client.query(sql)
      for result in [first, second] {
        #expect(result.schema?.fields.map(\.name) == ["name", "n"])
        #expect(result.totalRows == 3)
        let rows = try await result.rows.collect()
        #expect(JobsIT.scalars(rows, "name") == ["a", "b", "c"])
        #expect(JobsIT.scalars(rows, "n") == ["1", "2", "3"])
        #expect(result.statementType == .select)
      }
      #expect(first.jobID != nil)
      #expect(first.jobID != second.jobID)
    }
  }

  // Baseline: U.QueryJobConfiguration.01 (tableDefinitions)
  // Design: §6.2 — tableDefinitions is not allowlisted, so this runs through jobs.insert.
  @Test func tableDefinitionsQueryATemporaryExternalTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
      try await CloudStorage().upload(
        bucket: bucket, name: "ext.csv", data: Data("x,1\ny,2\n".utf8), contentType: "text/csv")
      var configuration = QueryJobConfiguration("SELECT name FROM ext ORDER BY n")
      configuration.tableDefinitions = [
        "ext": ExternalDataConfiguration(
          sourceURIs: ["gs://\(bucket)/ext.csv"], format: .csv,
          schema: Schema([Field("name", .string), Field("n", .int64)]))
      ]
      let result = try await client.query(configuration)
      #expect(result.jobID != nil)
      #expect(JobsIT.scalars(try await result.rows.collect(), "name") == ["x", "y"])
    }
  }

  // Baseline: IT-103
  @Test func multiPageResultsAreFetchedLazily() async throws {
    let client = try IntegrationTest.makeClient()
    var configuration = QueryJobConfiguration(
      "SELECT x FROM UNNEST(GENERATE_ARRAY(1, 25)) AS x ORDER BY x")
    configuration.maxResults = 10
    let result = try await client.query(configuration)
    #expect(result.totalRows == 25)
    var pageSizes: [Int] = []
    var values: [String?] = []
    for try await page in result.rows.pages {
      pageSizes.append(page.items.count)
      values += JobsIT.scalars(page.items, "x")
    }
    #expect(pageSizes.count >= 3)
    #expect(values == (1...25).map { String($0) })
  }

  // Baseline: IT-104, IT-112
  @Test func dmlReportsAffectedRows() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let insert = try await client.query(
        "INSERT INTO \(JobsIT.sql(table)) (name, n) VALUES ('d', 4), ('e', 5)")
      #expect(insert.numDMLAffectedRows == 2)
      #expect(insert.dmlStats?.insertedRowCount == 2)
      #expect(insert.statementType == .insert)
      #expect(try await insert.rows.collect().isEmpty)

      let update = try await client.query(
        "UPDATE \(JobsIT.sql(table)) SET n = n * 10 WHERE n > 3")
      #expect(update.dmlStats?.updatedRowCount == 2)

      let delete = try await client.query("DELETE FROM \(JobsIT.sql(table)) WHERE n < 3")
      #expect(delete.dmlStats?.deletedRowCount == 2)
      #expect(delete.statementType == .delete)
    }
  }

  // Baseline: IT-105
  @Test func ddlCreatesATable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = JobsIT.table(dataset)
      let result = try await client.query(
        "CREATE OR REPLACE TABLE \(JobsIT.sql(table)) AS SELECT 17 AS v")
      #expect(try await result.rows.collect().isEmpty)
      #expect(try await JobsIT.column(client, "SELECT v FROM \(JobsIT.sql(table))", "v") == ["17"])
    }
  }

  // Baseline: IT-107
  @Test func invalidQueriesSurfaceServiceReasons() async throws {
    let client = try IntegrationTest.makeClient()
    let invalid = await #expect(throws: BigQueryError.self) {
      try await client.query("SELECT * FROM")
    }
    #expect(invalid?.reason == "invalidQuery")

    let missing = await #expect(throws: BigQueryError.self) {
      try await client.query(
        "SELECT * FROM `\(client.projectID).\(IntegrationTest.uniqueName(JobsIT.slice)).t`")
    }
    #expect(missing?.isNotFound == true)
  }

  // Design: §4.3 — a failing query has the same kind and reason on the fast and slow paths.
  @Test(arguments: [
    "SELECT * FROM",
    "SELECT ERROR('swift runtime failure')",
    "SELECT * FROM `swift_bq_it_missing_jobs.t`",
  ])
  func queryFailuresMatchOnBothPaths(sql: String) async throws {
    let client = try IntegrationTest.makeClient()
    let fast = await #expect(throws: BigQueryError.self) {
      try await client.query(sql)
    }
    let slow = await #expect(throws: BigQueryError.self) {
      try await client.query(QueryJobConfiguration(sql), jobID: JobsIT.jobID())
    }
    #expect(fast?.kind == .job)
    #expect(slow?.kind == .job)
    #expect(fast?.reason == slow?.reason)
    #expect(fast?.isNotFound == slow?.isNotFound)
    #expect(slow?.jobID != nil)
  }

  // Baseline: IT-063, IT-064
  @Test func failingJobsReportTheJobError() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let dml = await #expect(throws: BigQueryError.self) {
        try await client.query(
          QueryJobConfiguration(
            "INSERT INTO \(JobsIT.sql(table)) (name, n) VALUES ('x', CAST('nan' AS INT64))"),
          jobID: JobsIT.jobID())
      }
      #expect(dml?.kind == .job)
      #expect(dml?.reason == "invalidQuery")

      let script = await #expect(throws: BigQueryError.self) {
        try await client.query("SELECT 1; SELECT ERROR('swift script failure');")
      }
      #expect(script?.message.contains("swift script failure") == true)
    }
  }

  // Baseline: IT-065
  @Test func timestampsAreMicrosecondsSinceTheEpoch() async throws {
    let client = try IntegrationTest.makeClient()
    let values = try await JobsIT.column(
      client, "SELECT TIMESTAMP '2024-01-01 00:00:00.123456 UTC' AS ts", "ts")
    #expect(values == ["1704067200123456"])
  }

  // Baseline: IT-001, IT-066
  @Test func maximumTimestampIsLossless() async throws {
    let client = try IntegrationTest.makeClient()
    let values = try await JobsIT.column(
      client, "SELECT TIMESTAMP '9999-12-31 23:59:59.999999 UTC' AS ts", "ts")
    #expect(values == ["253402300799999999"])
  }

  // Baseline: IT-106
  @Test func slowDDLFallsBackToPolling() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice, location: "US") {
      dataset in
      let table = JobsIT.table(dataset, "slow_ddl")
      var ddl = QueryJobConfiguration(
        """
        CREATE OR REPLACE TABLE \(table.tableID) AS
        SELECT unique_key, agency, complaint_type
        FROM `bigquery-public-data.new_york.311_service_requests`
        """)
      ddl.defaultDataset = dataset
      let result = try await client.query(ddl)
      #expect(result.jobID != nil)
      #expect(try await result.rows.collect().isEmpty)

      let rows = try await client.query("SELECT * FROM \(JobsIT.sql(table)) LIMIT 5").rows.collect()
      #expect(rows.count == 5)
      #expect(rows.allSatisfy { $0[0] == $0["unique_key"] && $0[1] == $0["agency"] })
    }
  }

  // Baseline: IT-068, IT-101
  @Test func queryWithJobIDExposesStatistics() async throws {
    let client = try IntegrationTest.makeClient()
    let id = JobID(projectID: client.projectID, jobID: JobsIT.jobID().jobID)
    var configuration = QueryJobConfiguration(
      "SELECT COUNT(*) AS c FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS x")
    configuration.useQueryCache = false
    let result = try await client.query(configuration, jobID: id)
    #expect(result.jobID?.jobID == id.jobID)
    #expect(result.jobID?.projectID == client.projectID)
    #expect(JobsIT.scalars(try await result.rows.collect(), "c") == ["1000"])
    let job = try await JobsIT.job(client, result.jobID)
    let statistics = try #require(job.statistics?.query)
    #expect(!statistics.queryPlan.isEmpty)
    #expect(statistics.totalSlotMs != nil)
    #expect(statistics.statementType == .select)
  }

  // Baseline: IT-108
  @Test func sessionsCarryTemporaryTables() async throws {
    let client = try IntegrationTest.makeClient()
    var create = QueryJobConfiguration("CREATE TEMP TABLE swift_tmp AS SELECT 42 AS v")
    create.createSession = true
    let created = try await client.query(create)
    let sessionID = try #require(created.sessionInfo?.sessionID)
    #expect(!sessionID.isEmpty)

    var read = QueryJobConfiguration("SELECT v FROM _SESSION.swift_tmp")
    read.connectionProperties = [.sessionID(sessionID)]
    let result = try await client.query(read, location: created.location)
    #expect(JobsIT.scalars(try await result.rows.collect(), "v") == ["42"])
    #expect(result.sessionInfo?.sessionID == sessionID)
    _ = try await client.query(
      {
        var end = QueryJobConfiguration("CALL BQ.ABORT_SESSION()")
        end.connectionProperties = [.sessionID(sessionID)]
        return end
      }(), location: created.location)
  }

  // Baseline: IT-115, IT-147
  @Test func dryRunReportsParametersAndBytes() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let result = try await client.dryRun(
        QueryJobConfiguration("SELECT name FROM \(JobsIT.sql(table)) WHERE n > @min"))
      #expect(result.schema?.fields.map(\.name) == ["name"])
      #expect(result.totalBytesProcessed != nil)
      #expect(result.referencedTables.map(\.tableID) == [table.tableID])
      #expect(result.undeclaredParameters.map(\.name) == ["min"])
      #expect(result.undeclaredParameters.map(\.type) == ["INT64"])
      #expect(result.statementType == .select)

      await #expect(throws: BigQueryError.self) {
        var configuration = QueryJobConfiguration("SELECT 1")
        configuration.dryRun = true
        _ = try await client.query(configuration)
      }
    }
  }

  // Baseline: IT-170, IT-171
  @Test func statelessQueriesHaveAQueryIDAndNoJob() async throws {
    let client = try IntegrationTest.makeClient()
    var optional = QueryJobConfiguration("SELECT 1 AS one")
    optional.jobCreationMode = .optional
    let stateless = try await client.query(optional)
    #expect(stateless.queryID?.isEmpty == false)
    #expect(JobsIT.scalars(try await stateless.rows.collect(), "one") == ["1"])
    if stateless.jobCreationReason != nil {
      // The service may still create a job; its ID is then the query ID.
      #expect(stateless.jobID?.jobID == stateless.queryID)
    }

    // A configuration outside the jobs.query allowlist creates a job, and has no query ID.
    var slow = QueryJobConfiguration("SELECT 1 AS one")
    slow.priority = .interactive
    let slowResult = try await client.query(slow)
    #expect(slowResult.jobID != nil)
    #expect(slowResult.queryID == nil)

    // Results of an explicitly created job have no query ID.
    let job = try await client.createJob(.query(QueryJobConfiguration("SELECT 1 AS one")))
    let explicit = try await client.getQueryResults(job.id)
    #expect(explicit.jobID?.jobID == job.id.jobID)
    #expect(explicit.queryID == nil)

    var required = QueryJobConfiguration("SELECT 1 AS one")
    required.jobCreationMode = .required
    let stateful = try await client.query(required)
    #expect(stateful.jobID != nil)
    #expect(stateful.queryID != nil)
  }

  // Baseline: IT-102, IT-156, IT-172
  @Test func euLocationIsHonored() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice, location: "EU") {
      dataset in
      let table = try await JobsIT.createSampleTable(
        client, JobsIT.table(dataset), location: "EU")
      let sql = "SELECT name FROM \(JobsIT.sql(table)) ORDER BY n"

      let withJob = try await client.query(
        QueryJobConfiguration(sql), jobID: JobsIT.jobID(location: "EU"))
      #expect(withJob.jobID?.location == "EU")
      #expect(JobsIT.scalars(try await withJob.rows.collect(), "name") == ["a", "b", "c"])
      let job = try await client.getJob(try #require(withJob.jobID))
      #expect(job?.id.location == "EU")
      #expect(try await client.getJob(JobID(jobID: withJob.jobID!.jobID, location: "US")) == nil)

      var stateless = QueryJobConfiguration(sql)
      stateless.jobCreationMode = .optional
      let fast = try await client.query(stateless, location: "EU")
      #expect(fast.location == "EU")
      #expect(JobsIT.scalars(try await fast.rows.collect(), "name") == ["a", "b", "c"])

      let wrong = await #expect(throws: BigQueryError.self) {
        try await client.query(QueryJobConfiguration(sql), location: "US")
      }
      #expect(wrong?.isNotFound == true)
    }
  }

  // Baseline: IT-173
  @Test func timeoutReportsTheRunningJob() async throws {
    let client = try IntegrationTest.makeClient()
    var configuration = QueryJobConfiguration(
      """
      SELECT COUNT(*) FROM UNNEST(GENERATE_ARRAY(1, 200000)) AS a
      CROSS JOIN UNNEST(GENERATE_ARRAY(1, 200000)) AS b WHERE MOD(a * b, 7) = 3
      """)
    configuration.useQueryCache = false
    let error = await #expect(throws: BigQueryError.self) {
      try await client.query(configuration, timeout: .seconds(2))
    }
    #expect(error?.kind == .timeout)
    let id = try #require(error?.jobID)
    #expect(try await client.cancelJob(id))
  }

  // Baseline: IT-169
  // Design: §5.2 — a 409 on the first attempt is the caller's collision and is not recovered.
  @Test func reusedJobIDIsReportedAsDuplicate() async throws {
    let client = try IntegrationTest.makeClient()
    let id = JobsIT.jobID()
    _ = try await client.createJob(.query(QueryJobConfiguration("SELECT 1")), id: id)
    let error = await #expect(throws: BigQueryError.self) {
      try await client.query(QueryJobConfiguration("SELECT 1"), jobID: id)
    }
    #expect(error?.httpStatusCode == 409)
  }

  // Baseline: IT-113
  @Test func transactionsReportTransactionInfo() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let id = JobsIT.jobID()
      _ = try await client.query(
        QueryJobConfiguration(
          """
          BEGIN TRANSACTION;
          INSERT INTO \(JobsIT.sql(table)) (name, n) VALUES ('t', 9);
          DELETE FROM \(JobsIT.sql(table)) WHERE n = 1;
          COMMIT TRANSACTION;
          """), jobID: id)
      var children: [Job] = []
      for try await job in client.listJobs(parentJob: id) { children.append(job) }
      #expect(children.count == 4)
      let full = try await withThrowingTaskGroup(of: Job?.self) { group in
        for child in children { group.addTask { try await client.getJob(child.id) } }
        return try await group.reduce(into: [Job]()) { if let job = $1 { $0.append(job) } }
      }
      #expect(full.contains { $0.statistics?.transactionInfo?.transactionID.isEmpty == false })
    }
  }

  // Baseline: IT-114
  @Test func scriptsReportChildJobsAndStatistics() async throws {
    let client = try IntegrationTest.makeClient()
    let id = JobsIT.jobID()
    let result = try await client.query(
      QueryJobConfiguration(
        """
        DECLARE total INT64 DEFAULT 0;
        SET total = (SELECT SUM(x) FROM UNNEST([1, 2, 3]) AS x);
        SELECT total AS total;
        """), jobID: id)
    #expect(JobsIT.scalars(try await result.rows.collect(), "total") == ["6"])
    let parent = try #require(try await client.getJob(id))
    #expect((parent.statistics?.numChildJobs ?? 0) >= 2)
    #expect(parent.statistics?.query?.statementType == .script)

    var children: [Job] = []
    for try await job in client.listJobs(parentJob: id) { children.append(job) }
    #expect(children.count == Int(parent.statistics?.numChildJobs ?? -1))
    let child = try await JobsIT.job(client, children.first?.id)
    #expect(child.statistics?.parentJobID == id.jobID)
    let script = try #require(child.statistics?.scriptStatistics)
    #expect(script.evaluationKind != nil)
    #expect(!script.stackFrames.isEmpty)
  }

  // Baseline: IT-142
  @Test func searchQueriesReportSearchStatistics() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      let result = try await client.query(
        QueryJobConfiguration("SELECT * FROM \(JobsIT.sql(table)) AS t WHERE SEARCH(t, 'a')"),
        jobID: JobsIT.jobID())
      let job = try await JobsIT.job(client, result.jobID)
      #expect(job.statistics?.query?.searchStatistics?.indexUsageMode == .unused)
    }
  }
}
