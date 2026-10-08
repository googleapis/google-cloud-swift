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

/// Live tests of the jobs API, and of query, copy, and extract jobs.
@Suite(.enabled(if: integrationTestsEnabled()))
struct JobIntegrationTests {
  // Baseline: IT-129, IT-130, IT-131
  @Test func listJobsHonorsFieldsAndCreationBounds() async throws {
    let client = try IntegrationTest.makeClient()
    let created = try await client.createJob(
      .query(QueryJobConfiguration("SELECT 1")), id: JobsIT.jobID())
    _ = try await client.waitForJob(created.id)
    let creation = try #require(created.statistics?.creationTime)

    var listed: [Job] = []
    for try await job in client.listJobs(pageSize: 20) {
      listed.append(job)
      if listed.count >= 20 { break }
    }
    #expect(!listed.isEmpty)
    #expect(listed.allSatisfy { !$0.id.jobID.isEmpty && $0.status.state.rawValue != "" })

    var masked: [Job] = []
    for try await job in client.listJobs(selectedFields: ["user_email"], pageSize: 5) {
      masked.append(job)
      if masked.count >= 5 { break }
    }
    #expect(masked.allSatisfy { $0.userEmail != nil && $0.statistics == nil })

    var bounded: [Job] = []
    for try await job in client.listJobs(
      minCreationTime: creation.addingTimeInterval(-1),
      maxCreationTime: creation.addingTimeInterval(1))
    {
      bounded.append(job)
    }
    #expect(bounded.contains { $0.id.jobID == created.id.jobID })
    #expect(
      bounded.allSatisfy {
        guard let time = $0.statistics?.creationTime else { return false }
        return abs(time.timeIntervalSince(creation)) <= 1.001
      })
  }

  // Baseline: IT-132, IT-135, IT-136, IT-138
  @Test func copyJobCopiesRowsWithLabelsAndExpiration() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let source = try await JobsIT.createSampleTable(client, JobsIT.table(dataset, "src"))
      let destination = JobsIT.table(dataset, "dst")
      let expiration = Date().addingTimeInterval(3600)
      var copy = CopyJobConfiguration(sourceTable: source, destinationTable: destination)
      copy.labels = ["swift-it": "copy"]
      copy.destinationExpirationTime = expiration
      let created = try await client.createJob(.copy(copy))

      let fetched = try #require(try await client.getJob(created.id))
      #expect(fetched.id == created.id)
      guard case .copy(let fetchedCopy) = fetched.configuration else {
        Issue.record("expected a copy configuration")
        return
      }
      #expect(fetchedCopy.labels == ["swift-it": "copy"])
      #expect(fetchedCopy.sourceTables == [source])
      let done = try await client.waitForJob(created.id)
      #expect(done.status.errorResult == nil)
      #expect(done.statistics?.copy?.copiedRows == 3)
      #expect((done.statistics?.copy?.copiedLogicalBytes ?? 0) > 0)
      #expect(
        try await JobsIT.column(client, "SELECT n FROM \(JobsIT.sql(destination)) ORDER BY n", "n")
          == ["1", "2", "3"])
    }
  }

  // Baseline: IT-134
  @Test func selectedFieldsLimitTheReturnedJob() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let source = try await JobsIT.createSampleTable(client, JobsIT.table(dataset, "src"))
      let copy = CopyJobConfiguration(
        sourceTable: source, destinationTable: JobsIT.table(dataset, "dst"))
      let created = try await client.createJob(.copy(copy), selectedFields: ["etag"])
      #expect(created.etag != nil)
      #expect(created.statistics == nil)
      #expect(created.selfLink == nil)
      #expect(created.userEmail == nil)
      guard case .copy(let createdCopy) = created.configuration else {
        Issue.record("expected a copy configuration")
        return
      }
      #expect(createdCopy.sourceTables == [source])

      let fetched = try #require(try await client.getJob(created.id, selectedFields: ["etag"]))
      #expect(fetched.id == created.id)
      #expect(fetched.configuration == created.configuration)
      #expect(fetched.etag != nil)
      #expect(fetched.statistics == nil)
      #expect(fetched.userEmail == nil)
      let done = try await client.waitForJob(created.id, timeout: .seconds(60))
      #expect(done.status.errorResult == nil)
    }
  }

  // Baseline: IT-133
  @Test func waitForJobWithPerCallOptions() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      var options = RequestOptions()
      options.retryPolicy = BigQueryRetryPolicy.unbounded().withAttemptLimit(1)
      let job = try await client.createJob(
        .query(QueryJobConfiguration("SELECT COUNT(*) FROM \(JobsIT.sql(table))")),
        options: options)
      let done = try await client.waitForJob(job.id, timeout: .seconds(120), options: options)
      #expect(done.status.state == .done)
      #expect(done.status.errorResult == nil)
    }
  }

  // Baseline: IT-137, IT-163
  @Test func snapshotAndCloneThroughCopyJobs() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let base = try await JobsIT.createSampleTable(client, JobsIT.table(dataset, "base"))
      let snapshot = JobsIT.table(dataset, "snap")
      let snap = try await client.createJob(
        .copy(
          CopyJobConfiguration(
            sourceTable: base, destinationTable: snapshot, operationType: .snapshot)))
      #expect(try await client.waitForJob(snap.id).status.errorResult == nil)

      let restored = JobsIT.table(dataset, "restored")
      let restore = try await client.createJob(
        .copy(
          CopyJobConfiguration(
            sourceTable: snapshot, destinationTable: restored, operationType: .restore)))
      #expect(try await client.waitForJob(restore.id).status.errorResult == nil)
      #expect(
        try await JobsIT.column(client, "SELECT n FROM \(JobsIT.sql(restored)) ORDER BY n", "n")
          == ["1", "2", "3"])

      let clone = JobsIT.table(dataset, "clone")
      let cloneJob = try await client.createJob(
        .copy(
          CopyJobConfiguration(sourceTable: base, destinationTable: clone, operationType: .clone)))
      let done = try await client.waitForJob(cloneJob.id)
      #expect(done.status.errorResult == nil)
      guard case .copy(let copy) = done.configuration else {
        Issue.record("expected a copy configuration")
        return
      }
      #expect(copy.operationType == .clone)
      #expect(
        try await JobsIT.column(client, "SELECT COUNT(*) AS c FROM \(JobsIT.sql(clone))", "c")
          == ["3"])
    }
  }

  // Baseline: IT-139, IT-140, IT-141, IT-143
  @Test func queryJobWritesADestinationTable() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let destination = JobsIT.table(dataset, "dest")
      var query = QueryJobConfiguration(
        "SELECT x, CAST(CURRENT_TIMESTAMP() AS STRING) AS now FROM UNNEST(GENERATE_ARRAY(1, 5)) AS x"
      )
      query.destinationTable = destination
      query.writeDisposition = .writeTruncate
      query.labels = ["swift-it": "query"]
      query.connectionProperties = [.timeZone("America/Los_Angeles")]
      query.rangePartitioning = RangePartitioning(
        field: "x", range: .init(start: 0, end: 10, interval: 2))
      let job = try await client.createJob(.query(query))
      let done = try await client.waitForJob(job.id)
      #expect(done.status.errorResult == nil)
      guard case .query(let fetched) = done.configuration else {
        Issue.record("expected a query configuration")
        return
      }
      #expect(fetched.labels == ["swift-it": "query"])
      #expect(fetched.connectionProperties == [.timeZone("America/Los_Angeles")])
      #expect(fetched.rangePartitioning == query.rangePartitioning)
      #expect(fetched.destinationTable == destination)
      let rows = try await client.getQueryResults(done.id).rows.collect()
      #expect(rows.count == 5)
      #expect(
        try await JobsIT.column(client, "SELECT COUNT(*) AS c FROM \(JobsIT.sql(destination))", "c")
          == ["5"])
    }
  }

  // Baseline: IT-151, IT-152
  @Test func cancelReportsWhetherTheJobExists() async throws {
    let client = try IntegrationTest.makeClient()
    var query = QueryJobConfiguration(
      """
      SELECT COUNT(*) FROM UNNEST(GENERATE_ARRAY(1, 200000)) AS a
      CROSS JOIN UNNEST(GENERATE_ARRAY(1, 200000)) AS b
      """)
    query.useQueryCache = false
    let job = try await client.createJob(.query(query))
    #expect(try await client.cancelJob(job.id))
    do {
      let done = try await client.waitForJob(job.id, timeout: .seconds(120))
      #expect(done.status.state == .done)
    } catch let error as BigQueryError {
      #expect(error.kind == .job)
      #expect(error.reason == "stopped")
    }
    #expect(try await client.cancelJob(JobsIT.jobID()) == false)
  }

  // Baseline: IT-047
  @Test func deleteJobRemovesItsMetadata() async throws {
    let client = try IntegrationTest.makeClient()
    let id = JobsIT.jobID(location: "us-east1")
    _ = try await client.createJob(.query(QueryJobConfiguration("SELECT 1")), id: id)
    _ = try await client.waitForJob(id)
    #expect(try await client.deleteJob(id))
    #expect(try await client.getJob(id) == nil)
  }

  // Baseline: IT-148, IT-150
  @Test func extractJobWritesCSVToCloudStorage() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
        var extract = ExtractJobConfiguration(
          source: .table(table), destinationURIs: ["gs://\(bucket)/out.csv"], format: .csv)
        extract.printHeader = true
        extract.labels = ["swift-it": "extract"]
        let job = try await client.createJob(.extract(extract))
        let done = try await client.waitForJob(job.id)
        #expect(done.status.errorResult == nil)
        guard case .extract(let fetched) = done.configuration else {
          Issue.record("expected an extract configuration")
          return
        }
        #expect(fetched.labels == ["swift-it": "extract"])
        #expect(done.statistics?.extract?.destinationURIFileCounts == [1])
        let csv = String(
          decoding: try await CloudStorage().download(bucket: bucket, name: "out.csv"),
          as: UTF8.self)
        #expect(csv.split(separator: "\n").first == "name,n")
        #expect(Set(csv.split(separator: "\n").dropFirst()) == ["a,1", "b,2", "c,3"])
      }
    }
  }

  // Baseline: IT-149
  @Test func extractJobExportsAModel() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let model = ModelID(dataset: dataset, modelID: "model_\(IntegrationTest.randomHex())")
      _ = try await client.query(
        """
        CREATE MODEL `\(model.projectID!).\(model.datasetID).\(model.modelID)`
        OPTIONS (model_type = 'linear_reg', max_iterations = 1, learn_rate = 0.4,
                 learn_rate_strategy = 'constant')
        AS SELECT 'a' AS f1, 2.0 AS label UNION ALL SELECT 'b' AS f1, 3.8 AS label
        """)
      try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
        let job = try await client.createJob(
          .extract(
            ExtractJobConfiguration(
              source: .model(model), destinationURIs: ["gs://\(bucket)/model"])))
        let done = try await client.waitForJob(job.id, timeout: .seconds(300))
        #expect(done.status.errorResult == nil)
        guard case .extract(let fetched) = done.configuration else {
          Issue.record("expected an extract configuration")
          return
        }
        #expect(fetched.source.model == model)
        #expect(!(try await CloudStorage().listObjects(bucket: bucket, prefix: "model/")).isEmpty)
      }
    }
  }

  // Baseline: IT-188
  @Test func exportDataReportsExportStatistics() async throws {
    let client = try IntegrationTest.makeClient()
    try await IntegrationTest.withTemporaryDataset(client, slice: JobsIT.slice) { dataset in
      let table = try await JobsIT.createSampleTable(client, JobsIT.table(dataset))
      try await IntegrationTest.withTemporaryBucket(slice: JobsIT.slice) { bucket in
        let result = try await client.query(
          QueryJobConfiguration(
            """
            EXPORT DATA OPTIONS (uri = 'gs://\(bucket)/export/*.csv', format = 'CSV', overwrite = true)
            AS SELECT * FROM \(JobsIT.sql(table))
            """), jobID: JobsIT.jobID())
        let job = try await JobsIT.job(client, result.jobID)
        let statistics = try #require(job.statistics?.query?.exportDataStatistics)
        #expect(statistics.rowCount == 3)
        #expect((statistics.fileCount ?? 0) >= 1)
      }
    }
  }
}
