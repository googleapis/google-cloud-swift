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
import GoogleCloudBigQueryV2
import GoogleGax
import Testing

@testable import GoogleCloudBigQuery

@Suite struct BigQueryClientQueryTests {
  private func names(_ result: QueryResult) async throws -> [String] {
    try await result.rows.collect().map {
      guard case .scalar(let value) = $0["name"] ?? .null else { return "" }
      return value
    }
  }

  private func slowConfiguration(_ sql: String = "SELECT name FROM t") -> QueryJobConfiguration {
    var configuration = QueryJobConfiguration(sql)
    configuration.priority = .batch
    return configuration
  }

  // Baseline: U.BigQueryImpl.46
  @Test func queryWithJobIDInsertsWaitsAndReadsRows() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "q", state: "RUNNING"))
    fake.enqueue(json: JobFixtures.queryResults(id: "q", rows: ["a", "b"], totalRows: 2))
    fake.enqueue(
      json: JobFixtures.job(
        id: "q", statistics: #"{"query": {"statementType": "SELECT", "totalBytesBilled": "10"}}"#))
    let result = try await fake.client().query(
      QueryJobConfiguration("SELECT name FROM t"), jobID: JobID(jobID: "q"))
    #expect(try await self.names(result) == ["a", "b"])
    #expect(result.totalRows == 2)
    #expect(result.jobID?.jobID == "q")
    #expect(result.statementType == .select)
    #expect(result.totalBytesBilled == 10)
    let requests = fake.requests
    #expect(requests.map(\.method) == [.post, .get, .get])
    #expect(requests[0].path == "/bigquery/v2/projects/test-project/jobs")
    #expect(requests[1].path == "/bigquery/v2/projects/test-project/queries/q")
    #expect(requests[1].queryValue("timeoutMs") == "10000")
    #expect(requests[2].path == "/bigquery/v2/projects/test-project/jobs/q")
  }

  // Baseline: U.BigQueryImpl.47
  @Test func fastPathSendsQueryRequest() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"], totalRows: 1))
    var configuration = QueryJobConfiguration("SELECT name FROM t")
    configuration.defaultDataset = DatasetID(datasetID: "d")
    configuration.useQueryCache = false
    let result = try await fake.client().query(configuration)
    #expect(try await self.names(result) == ["a"])
    #expect(fake.requests.count == 1)
    let request = try #require(fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/bigquery/v2/projects/test-project/queries")
    let body = try request.jsonBody()
    #expect(body["query"] as? String == "SELECT name FROM t")
    #expect(body["useQueryCache"] as? Bool == false)
    #expect(body["useLegacySql"] as? Bool == false)
    #expect((body["requestId"] as? String)?.isEmpty == false)
    let dataset = body["defaultDataset"] as? [String: Any]
    #expect(dataset?["projectId"] as? String == "test-project")
    #expect(dataset?["datasetId"] as? String == "d")
    #expect((body["location"] as? String ?? "").isEmpty)
    #expect(body["timeoutMs"] == nil)
  }

  // Baseline: U.BigQueryImpl.48
  @Test func fastPathForwardsJobTimeout() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults())
    var configuration = QueryJobConfiguration("SELECT 1")
    configuration.jobTimeout = .seconds(5)
    _ = try await fake.client().query(configuration)
    #expect(fake.requests.count == 1)
    #expect(try fake.requests[0].jsonBody()["jobTimeoutMs"] as? String == "5000")
  }

  // Baseline: U.BigQueryImpl.49
  @Test func requiredJobCreationStillUsesJobsQuery() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(id: "created"))
    var configuration = QueryJobConfiguration("SELECT 1")
    configuration.jobCreationMode = .required
    let result = try await fake.client().query(configuration)
    #expect(result.jobID?.jobID == "created")
    #expect(fake.requests.map(\.path) == ["/bigquery/v2/projects/test-project/queries"])
    #expect(
      try fake.requests[0].jsonBody()["jobCreationMode"] as? String == "JOB_CREATION_REQUIRED")
  }

  // Baseline: U.BigQueryImpl.50
  @Test func fastPathSendsClientLocationAndExposesStatistics() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        extra: #""totalBytesProcessed": "42", "cacheHit": true, "location": "EU""#))
    let result = try await fake.client(location: "EU").query("SELECT 1")
    #expect(try fake.requests[0].jsonBody()["location"] as? String == "EU")
    #expect(result.totalBytesProcessed == 42)
    #expect(result.cacheHit == true)
    #expect(result.location == "EU")
  }

  // Baseline: U.BigQueryImpl.51
  @Test func fastPathReadsLaterPagesFromGetQueryResults() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"], totalRows: 2, pageToken: "t"))
    fake.enqueue(json: JobFixtures.queryResults(rows: ["b"], totalRows: 2))
    let result = try await fake.client().query("SELECT name FROM t")
    #expect(try await self.names(result) == ["a", "b"])
    #expect(fake.requests.count == 2)
    #expect(fake.requests[1].path == "/bigquery/v2/projects/test-project/queries/j")
    #expect(fake.requests[1].queryValue("pageToken") == "t")
  }

  // Baseline: U.BigQueryImpl.52, U.BigQueryImpl.54
  @Test func incompleteFastPathPollsGetQueryResults() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        complete: false, schema: false, extra: #""jobCreationReason": {"code": "LONG_RUNNING"}"#))
    fake.enqueue(json: JobFixtures.queryResults(complete: false, schema: false))
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"], totalRows: 1))
    fake.enqueue(json: JobFixtures.job(statistics: #"{"query": {"statementType": "SELECT"}}"#))
    let result = try await fake.client().query("SELECT name FROM t")
    #expect(try await self.names(result) == ["a"])
    #expect(result.jobCreationReason == "LONG_RUNNING")
    #expect(result.statementType == .select)
    #expect(fake.requests.map(\.method) == [.post, .get, .get, .get])
    #expect(fake.requests[3].path == "/bigquery/v2/projects/test-project/jobs/j")
  }

  // Baseline: U.BigQueryImpl.53
  @Test func getQueryResultsForwardsPageSizeAndStartIndex() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"], totalRows: 2, pageToken: "t"))
    fake.enqueue(json: JobFixtures.job())
    fake.enqueue(json: JobFixtures.queryResults(rows: ["b"], totalRows: 2))
    let result = try await fake.client().getQueryResults(
      JobID(jobID: "j"), startIndex: 3, pageSize: 5)
    #expect(try await self.names(result) == ["a", "b"])
    let first = fake.requests[0]
    #expect(first.queryValue("maxResults") == "5")
    #expect(first.queryValue("startIndex") == "3")
    let next = fake.requests[2]
    #expect(next.queryValue("maxResults") == "5")
    #expect(next.queryValue("startIndex") == nil)
    #expect(next.queryValue("pageToken") == "t")
  }

  // Baseline: U.BigQueryImpl.55
  // Design: §6.1
  @Test func queryTimeoutIsSentAndStatisticsAreExposed() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        schema: false, totalRows: 0,
        extra: #"""
          "statementType": "UPDATE", "totalBytesBilled": "100", "totalBytesProcessed": "90",
          "totalSlotMs": "7", "numDmlAffectedRows": "3", "sessionInfo": {"sessionId": "s"},
          "dmlStats": {"updatedRowCount": "3"}, "creationTime": "1000", "startTime": "2000",
          "endTime": "3000"
          """#))
    fake.enqueue(json: JobFixtures.queryResults(schema: false, totalRows: 0))
    let result = try await fake.client().query(
      QueryJobConfiguration("UPDATE t SET x = 1 WHERE true"), timeout: .seconds(30))
    #expect(try fake.requests[0].jsonBody()["timeoutMs"] as? Int == 30000)
    #expect(result.statementType == .update)
    #expect(result.totalBytesBilled == 100)
    #expect(result.totalBytesProcessed == 90)
    #expect(result.totalSlotMs == 7)
    #expect(result.numDMLAffectedRows == 3)
    #expect(result.dmlStats?.updatedRowCount == 3)
    #expect(result.totalRows == 0)
    #expect(result.sessionInfo?.sessionID == "s")
    #expect(result.creationTime == Date(timeIntervalSince1970: 1))
    #expect(result.endTime == Date(timeIntervalSince1970: 3))
    #expect(result.schema == nil)
    #expect(try await result.rows.collect().isEmpty)
  }

  // Baseline: U.BigQueryImpl.57
  @Test func getQueryResultsUsesTheJobProjectAndLocation() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults())
    fake.enqueue(json: JobFixtures.job(project: "other", location: "EU"))
    let result = try await fake.client().getQueryResults(
      JobID(projectID: "other", jobID: "j", location: "EU"))
    #expect(result.jobID == JobID(projectID: "other", jobID: "j", location: "EU"))
    let request = fake.requests[0]
    #expect(request.path == "/bigquery/v2/projects/other/queries/j")
    #expect(request.queryValue("location") == "EU")
    #expect(request.queryValue("timeoutMs") == "10000")
    #expect(fake.requests[1].path == "/bigquery/v2/projects/other/jobs/j")
  }

  // Baseline: U.BigQueryImpl.58, U.Job.09
  @Test func getQueryResultsRetriesTransientErrors() async throws {
    let fake = FakeHTTPTransport()
    for status in [500, 502, 503, 504] { fake.enqueueError(status: status) }
    fake.enqueueError(status: 403, reasons: ["rateLimitExceeded"])
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"]))
    fake.enqueue(json: JobFixtures.job())
    let result = try await fake.client().getQueryResults(JobID(jobID: "j"))
    #expect(try await self.names(result) == ["a"])
    #expect(fake.requests.count == 7)
  }

  // Baseline: U.Job.09
  // Design: §6.1
  @Test func failedQueryReportsTheJobError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 400, reasons: ["invalidQuery"], message: "Syntax error")
    fake.enqueue(json: JobFixtures.job(errorReason: "invalidQuery"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().getQueryResults(JobID(jobID: "j"))
    }
    #expect(error?.kind == .job)
    #expect(error?.reason == "invalidQuery")
    #expect(error?.jobID?.jobID == "j")
    #expect(fake.requests.count == 2)
  }

  // Baseline: U.Job.06
  @Test func getQueryResultsOfANonQueryJobIsAServiceError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 400, reasons: ["invalid"], message: "not a query job")
    fake.enqueue(json: JobFixtures.job(configuration: #"{"copy": {}}"#))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().getQueryResults(JobID(jobID: "j"))
    }
    #expect(error?.kind == .service)
    #expect(error?.httpStatusCode == 400)
  }

  // Baseline: U.BigQueryImpl.61
  @Test func queryRejectsDryRun() async throws {
    let fake = FakeHTTPTransport()
    var configuration = QueryJobConfiguration("SELECT 1")
    configuration.dryRun = true
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query(configuration)
    }
    #expect(error?.kind == .invalidArgument)
    #expect(fake.requests.isEmpty)
  }

  // Baseline: U.BigQueryImpl.61
  @Test func dryRunReturnsStatistics() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.job(
        statistics: #"""
          {"totalBytesProcessed": "123", "query": {
            "totalBytesProcessed": "123", "statementType": "SELECT",
            "schema": {"fields": [{"name": "x", "type": "INT64"}]},
            "referencedTables": [{"projectId": "p", "datasetId": "d", "tableId": "t"}],
            "undeclaredQueryParameters": [{"name": "age", "parameterType": {"type": "INT64"}}]}}
          """#))
    let result = try await fake.client().dryRun(
      QueryJobConfiguration("SELECT x FROM d.t WHERE age > @age"), location: "EU")
    #expect(result.totalBytesProcessed == 123)
    #expect(result.statementType == .select)
    #expect(result.schema?.fields.map(\.name) == ["x"])
    #expect(result.referencedTables == [TableID(projectID: "p", datasetID: "d", tableID: "t")])
    #expect(result.undeclaredParameters == [UndeclaredQueryParameter(name: "age", type: "INT64")])
    let body = try fake.requests[0].jsonBody()
    let configuration = body["configuration"] as? [String: Any]
    #expect(configuration?["dryRun"] as? Bool == true)
    #expect((body["jobReference"] as? [String: Any])?["location"] as? String == "EU")
  }

  // Baseline: U.BigQueryImpl.62
  @Test func fastPathRetriesReuseTheRequestID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 500)
    fake.enqueueError(status: 503)
    fake.enqueue(json: JobFixtures.queryResults())
    _ = try await fake.client().query("INSERT INTO t VALUES (1)")
    let ids = try fake.requests.map { try $0.jsonBody()["requestId"] as? String }
    #expect(ids.count == 3)
    #expect(Set(ids).count == 1)
  }

  // Baseline: U.BigQueryImpl.63
  @Test func fastPathRateLimitErrorStatusReusesTheRequestID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 403, reasons: ["rateLimitExceeded"], message: "Exceeded rate limits")
    fake.enqueue(json: JobFixtures.queryResults())
    _ = try await fake.client().query("SELECT 1")
    let ids = try fake.requests.map { try $0.jsonBody()["requestId"] as? String }
    #expect(ids.count == 2)
    #expect(ids[0] == ids[1])
  }

  // Design: §5.2
  @Test func fastPathJobRateLimitUsesAFreshRequestID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        extra: #""errors": [{"reason": "jobRateLimitExceeded", "message": "too many"}]"#))
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"]))
    let result = try await fake.client().query("SELECT name FROM t")
    #expect(try await self.names(result) == ["a"])
    let ids = try fake.requests.map { try $0.jsonBody()["requestId"] as? String }
    #expect(ids.count == 2)
    #expect(ids[0] != ids[1])
  }

  // Baseline: U.BigQueryImpl.64
  @Test func jobRateLimitIsRecognizedByReason() {
    func error(_ reason: String) -> GoogleCloudBigQueryV2.ErrorProto {
      GoogleCloudBigQueryV2.ErrorProto().with { $0.reason = reason }
    }
    #expect(BigQueryClient.isJobRateLimit(error("rateLimitExceeded")))
    #expect(BigQueryClient.isJobRateLimit(error("jobRateLimitExceeded")))
    #expect(!BigQueryClient.isJobRateLimit(error("quotaExceeded")))
    #expect(!BigQueryClient.isJobRateLimit(error("invalidQuery")))
  }

  // Baseline: U.BigQueryImpl.65
  @Test func fastPathErrorsInASuccessfulResponseAreAJobError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        extra: #"""
          "errors": [{"reason": "invalidQuery", "message": "bad"}, {"reason": "other", "message": "x"}]
          """#))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query("SELECT oops")
    }
    #expect(error?.kind == .job)
    #expect(error?.errors.map(\.reason) == ["invalidQuery", "other"])
    #expect(error?.jobID?.jobID == "j")
  }

  // Design: §6.1
  @Test func statelessQueryHasAQueryIDAndNoJob() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(id: nil, rows: ["a"], extra: #""queryId": "qid""#))
    var configuration = QueryJobConfiguration("SELECT name FROM t")
    configuration.jobCreationMode = .optional
    let result = try await fake.client().query(configuration)
    #expect(result.jobID == nil)
    #expect(result.queryID == "qid")
    #expect(try await self.names(result) == ["a"])
    #expect(
      try fake.requests[0].jsonBody()["jobCreationMode"] as? String == "JOB_CREATION_OPTIONAL")
  }

  // Design: §6.1
  @Test func statelessResultWithMorePagesIsMalformed() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.queryResults(
        id: nil, rows: ["a"], pageToken: "next", extra: #""queryId": "qid""#))
    var configuration = QueryJobConfiguration("SELECT name FROM t")
    configuration.jobCreationMode = .optional
    await #expect(throws: RequestError.self) {
      try await fake.client().query(configuration)
    }
  }

  // Design: §6.1
  @Test func clientDefaultJobCreationModeApplies() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(id: nil))
    let client = BigQueryClient(
      projectID: "test-project", defaultJobCreationMode: .optional, transport: fake.transport())
    _ = try await client.query("SELECT 1")
    #expect(
      try fake.requests[0].jsonBody()["jobCreationMode"] as? String == "JOB_CREATION_OPTIONAL")
  }

  // Design: §6.1
  @Test func completeFastPathWithoutSchemaReadsGetQueryResultsOnce() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(schema: false))
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"]))
    let result = try await fake.client().query("BEGIN SELECT 'a' AS name; END")
    #expect(try await self.names(result) == ["a"])
    #expect(fake.requests.count == 2)
    #expect(fake.requests[1].path == "/bigquery/v2/projects/test-project/queries/j")
  }

  // Baseline: U.QueryRequestInfo.01
  @Test func fastPathEligibility() {
    var simple = QueryJobConfiguration("SELECT 1", parameters: .named(["x": .int64(1)]))
    simple.defaultDataset = DatasetID(datasetID: "d")
    simple.useQueryCache = true
    simple.maximumBytesBilled = 10
    simple.labels = ["k": "v"]
    simple.connectionProperties = [.timeZone("UTC")]
    simple.createSession = true
    simple.jobCreationMode = .required
    simple.maxResults = 10
    simple.jobTimeout = .seconds(1)
    simple.reservation = "r"
    #expect(simple.isFastPathEligible)

    let slow: [(inout QueryJobConfiguration) -> Void] = [
      { $0.destinationTable = TableID(datasetID: "d", tableID: "t") },
      { $0.createDisposition = .createNever },
      { $0.writeDisposition = .writeAppend },
      { $0.schemaUpdateOptions = [.allowFieldAddition] },
      { $0.userDefinedFunctions = [.inline("x")] },
      {
        $0.tableDefinitions = [
          "ext": ExternalDataConfiguration(sourceURIs: ["gs://b/f.csv"], format: .csv)
        ]
      },
      { $0.priority = .batch },
      { $0.allowLargeResults = true },
      { $0.flattenResults = false },
      { $0.destinationEncryption = EncryptionConfiguration(kmsKeyName: "k") },
      { $0.timePartitioning = TimePartitioning(type: .day) },
      {
        $0.rangePartitioning = RangePartitioning(
          field: "f", range: .init(start: 0, end: 1, interval: 1))
      },
      { $0.clustering = Clustering(fields: ["f"]) },
      { $0.scriptOptions = ScriptOptions(statementByteBudget: 1) },
      { $0.dryRun = true },
    ]
    for change in slow {
      var configuration = QueryJobConfiguration("SELECT 1")
      change(&configuration)
      #expect(!configuration.isFastPathEligible)
    }
  }

  // Baseline: U.QueryRequestInfo.02
  @Test func queryRequestCarriesTheConfiguration() throws {
    var configuration = QueryJobConfiguration(
      "SELECT @x", parameters: .named(["x": .string("v")]))
    configuration.labels = ["k": "v"]
    configuration.connectionProperties = [.sessionID("s")]
    configuration.createSession = false
    configuration.maximumBytesBilled = 100
    configuration.maxResults = 50
    configuration.jobTimeout = .milliseconds(1500)
    configuration.reservation = "projects/p/locations/US/reservations/r"
    let request = configuration.queryRequest(
      requestID: "rid", location: "US", jobCreationMode: .optional, timeout: .seconds(2),
      defaultProject: "p")
    #expect(request.requestId == "rid")
    #expect(request.location == "US")
    #expect(request.jobCreationMode == .jobCreationOptional)
    #expect(request.timeoutMs == 2000)
    #expect(request.maxResults == 50)
    #expect(request.jobTimeoutMs == 1500)
    #expect(request.labels == ["k": "v"])
    #expect(request.connectionProperties.map(\.key) == ["session_id"])
    #expect(request.createSession == false)
    #expect(request.maximumBytesBilled == 100)
    #expect(request.parameterMode == "NAMED")
    #expect(request.queryParameters.map(\.name) == ["x"])
    #expect(request.reservation == "projects/p/locations/US/reservations/r")
    #expect(request.useLegacySql == false)
  }

  // Baseline: U.QueryRequestInfo.03, U.BigQueryOptions.03
  @Test func everyQueryRequestAsksForInt64Timestamps() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"], pageToken: "t"))
    fake.enqueue(json: JobFixtures.queryResults(rows: ["b"]))
    let result = try await fake.client().query("SELECT name FROM t")
    _ = try await result.rows.collect()
    let body = try fake.requests[0].jsonBody()
    #expect((body["formatOptions"] as? [String: Any])?["useInt64Timestamp"] as? Bool == true)
    #expect(fake.requests[1].queryValue("formatOptions.useInt64Timestamp") == "true")
  }

  // Baseline: U.TableResult.01
  @Test func resultWithoutSchemaHasNoRows() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(schema: false))
    fake.enqueue(json: JobFixtures.queryResults(schema: false))
    let result = try await fake.client().query("CREATE TABLE d.t (x INT64)")
    #expect(result.schema == nil)
    #expect(result.rows.schema.fields.isEmpty)
    #expect(try await result.rows.collect().isEmpty)
  }

  // Baseline: U.TableResult.02
  @Test func resultRowsAreAccessibleByNameAndIndex() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a", "b"], totalRows: 2))
    let result = try await fake.client().query("SELECT name FROM t")
    #expect(result.totalRows == 2)
    #expect(result.rows.totalRows == 2)
    #expect(result.schema?.fields.map(\.name) == ["name"])
    let rows = try await result.rows.collect()
    #expect(rows[0][0] == .scalar("a"))
    #expect(rows[1]["NAME"] == .scalar("b"))
  }

  // Baseline: U.TableResult.03, U.Job.05
  @Test func slowPathResultsCarryJobStatistics() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "PENDING"))
    fake.enqueue(json: JobFixtures.queryResults(rows: [], totalRows: 0))
    fake.enqueue(
      json: JobFixtures.job(
        statistics: #"""
          {"creationTime": "1000", "startTime": "2000", "endTime": "3000", "totalSlotMs": "9",
           "sessionInfo": {"sessionId": "s"},
           "query": {"statementType": "SELECT", "totalBytesProcessed": "5", "totalBytesBilled": "6",
                     "cacheHit": false, "numDmlAffectedRows": "0"}}
          """#))
    let result = try await fake.client().query(self.slowConfiguration())
    #expect(result.statementType == .select)
    #expect(result.totalBytesProcessed == 5)
    #expect(result.totalBytesBilled == 6)
    #expect(result.totalSlotMs == 9)
    #expect(result.cacheHit == false)
    #expect(result.sessionInfo?.sessionID == "s")
    #expect(result.startTime == Date(timeIntervalSince1970: 2))
    #expect(result.schema?.fields.map(\.name) == ["name"])
    #expect(result.totalRows == 0)
    #expect(try await result.rows.collect().isEmpty)
  }

  // Baseline: U.Job.05
  @Test func slowPathEmptyResultWithoutSchema() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    fake.enqueue(json: JobFixtures.queryResults(schema: false, totalRows: 0))
    fake.enqueue(json: JobFixtures.job())
    let result = try await fake.client().query(self.slowConfiguration("DROP TABLE d.t"))
    #expect(result.schema == nil)
    #expect(try await result.rows.collect().isEmpty)
  }

  // Design: §6.3
  @Test func queryTimeoutReportsTheRunningJob() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "q", state: "RUNNING"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query(self.slowConfiguration(), timeout: .zero)
    }
    #expect(error?.kind == .timeout)
    #expect(error?.jobID?.jobID != nil)
    #expect(fake.requests.count == 1)
  }

  // Design: §6.1
  @Test func slowPathJobFailureIsAJobError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    fake.enqueue(json: JobFixtures.queryResults())
    fake.enqueue(json: JobFixtures.job(errorReason: "resourcesExceeded"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query(self.slowConfiguration())
    }
    #expect(error?.kind == .job)
    #expect(error?.reason == "resourcesExceeded")
  }

  // Design: §4.3
  @Test(arguments: [(400, "invalidQuery"), (403, "accessDenied"), (404, "notFound")])
  func fastPathRejectedQueryIsAJobError(status: Int, reason: String) async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: status, reasons: [reason], message: "rejected")
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query("SELECT name FROM t")
    }
    #expect(error?.kind == .job)
    #expect(error?.httpStatusCode == status)
    #expect(error?.reason == reason)
    #expect(error?.isNotFound == (reason == "notFound"))
    #expect(error?.jobID == nil)
    #expect(fake.requests.count == 1)
  }

  // Design: §4.3
  @Test(arguments: [(400, "invalidQuery"), (404, "notFound"), (409, "duplicate")])
  func slowPathRejectedQueryIsAJobError(status: Int, reason: String) async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: status, reasons: [reason], message: "rejected")
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query(
        QueryJobConfiguration("SELECT name FROM t"), jobID: JobID(jobID: "mine"))
    }
    #expect(error?.kind == .job)
    #expect(error?.httpStatusCode == status)
    #expect(error?.reason == reason)
    #expect(error?.isNotFound == (reason == "notFound"))
    #expect(error?.jobID?.jobID == "mine")
    #expect(fake.requests.count == 1)
  }

  // Design: §4.3
  @Test func slowPathMissingTableIsNotFound() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(errorReason: "notFound"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().query(self.slowConfiguration())
    }
    #expect(error?.kind == .job)
    #expect(error?.isNotFound == true)
  }

  // Design: §4.3
  @Test func authenticationFailureStaysAServiceError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 401, reasons: ["authError"])
    fake.enqueueError(status: 401, reasons: ["authError"])
    for configuration in [QueryJobConfiguration("SELECT 1"), self.slowConfiguration()] {
      let error = await #expect(throws: BigQueryError.self) {
        _ = try await fake.client().query(configuration)
      }
      #expect(error?.kind == .service)
      #expect(error?.httpStatusCode == 401)
    }
  }

  // Design: §4.3
  @Test func exhaustedRetriesStayAServiceError() {
    let rateLimited = BigQueryError(
      kind: .service, message: "Exceeded rate limits", httpStatusCode: 403,
      errors: [BigQueryError.Detail(reason: "rateLimitExceeded")])
    #expect(BigQueryClient.queryFailure(rateLimited, job: nil) == rateLimited)
    let unavailable = BigQueryError(kind: .service, message: "down", httpStatusCode: 503)
    #expect(BigQueryClient.queryFailure(unavailable, job: nil) == unavailable)
  }

  // Design: §6.1
  @Test func sqlQueryConvenienceForwardsPageSize() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.queryResults(rows: ["a"]))
    _ = try await fake.client().query("SELECT name FROM t", pageSize: 25)
    let body = try fake.requests[0].jsonBody()
    #expect(body["maxResults"] as? NSNumber == 25)
  }

  // Baseline: U.BigQueryImpl.61
  @Test func sqlDryRunConvenienceSendsDryRunWithParameters() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.job(
        statistics: #"{"query": {"totalBytesProcessed": "99", "statementType": "SELECT"}}"#))
    let estimate = try await fake.client().dryRun(
      "SELECT @x", parameters: .named(["x": .int64(7)]))
    #expect(estimate.totalBytesProcessed == 99)
    #expect(estimate.statementType == .select)
    let body = try fake.requests[0].jsonBody()
    let configuration = body["configuration"] as? [String: Any]
    let query = configuration?["query"] as? [String: Any]
    #expect(configuration?["dryRun"] as? Bool == true)
    #expect(query?["query"] as? String == "SELECT @x")
    #expect((query?["queryParameters"] as? [[String: Any]])?.first?["name"] as? String == "x")
  }
}
