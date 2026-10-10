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

@Suite struct BigQueryClientJobTests {
  private let copy = JobConfiguration.copy(
    CopyJobConfiguration(
      sourceTable: TableID(datasetID: "d", tableID: "src"),
      destinationTable: TableID(datasetID: "d", tableID: "dst")))

  private func jobReference(_ request: HTTPRequest) throws -> [String: Any] {
    try request.jsonBody()["jobReference"] as? [String: Any] ?? [:]
  }

  // Baseline: U.BigQueryImpl.32
  @Test func createJobSendsCallerJobID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "my-job", state: "RUNNING"))
    let job = try await fake.client().createJob(self.copy, id: JobID(jobID: "my-job"))
    #expect(job.id == JobID(projectID: "test-project", jobID: "my-job"))
    #expect(job.status.state == .running)
    let request = try #require(fake.requests.first)
    #expect(request.method == .post)
    #expect(request.path == "/bigquery/v2/projects/test-project/jobs")
    #expect(try self.jobReference(request)["jobId"] as? String == "my-job")
    #expect(try self.jobReference(request)["projectId"] as? String == "test-project")
    let configuration = try request.jsonBody()["configuration"] as? [String: Any]
    let copy = configuration?["copy"] as? [String: Any]
    let destination = copy?["destinationTable"] as? [String: Any]
    #expect(destination?["projectId"] as? String == "test-project")
    #expect(destination?["tableId"] as? String == "dst")
  }

  // Baseline: U.BigQueryImpl.33
  // Design: §5.2
  @Test func createJobRetriesTransportErrorsWithTheSameID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(.error(URLError(.cannotFindHost)))
    fake.enqueue(.error(URLError(.cannotConnectToHost)))
    fake.enqueue(json: JobFixtures.job(id: "x"))
    _ = try await fake.client(location: "EU").createJob(self.copy)
    #expect(fake.requests.count == 3)
    let ids = try fake.requests.map { try self.jobReference($0)["jobId"] as? String }
    #expect(Set(ids).count == 1)
    #expect(try self.jobReference(fake.requests[0])["location"] as? String == "EU")
  }

  // Baseline: U.BigQueryImpl.34
  @Test func createJobRetriesTransientStatusesAndRateLimitReasons() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 500)
    fake.enqueueError(status: 502)
    fake.enqueueError(status: 503)
    fake.enqueueError(status: 400, reasons: ["rateLimitExceeded"])
    fake.enqueue(json: JobFixtures.job())
    _ = try await fake.client().createJob(self.copy, id: JobID(jobID: "j"))
    #expect(fake.requests.count == 5)
  }

  // Baseline: U.BigQueryImpl.35, U.BigQueryImpl.36
  @Test func createJobHonorsPerCallRetryPolicy() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503)
    fake.enqueue(json: JobFixtures.job())
    var options = RequestOptions()
    options.retryPolicy = BigQueryRetryPolicy.unbounded().withAttemptLimit(1)
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().createJob(self.copy, options: options)
    }
    #expect(error?.httpStatusCode == 503)
    #expect(fake.requests.count == 1)

    options.retryPolicy = BigQueryRetryPolicy.unbounded().withAttemptLimit(4)
    let retried = FakeHTTPTransport()
    for _ in 0..<3 { retried.enqueueError(status: 503) }
    retried.enqueue(json: JobFixtures.job())
    _ = try await retried.client().createJob(self.copy, options: options)
    #expect(retried.requests.count == 4)
  }

  // Baseline: U.BigQueryImpl.37, U.JobInfo.02
  @Test func createJobAddsRequiredFieldsAndUsesTheJobProject() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(project: "other"))
    _ = try await fake.client().createJob(
      self.copy, id: JobID(projectID: "other", jobID: "j"), selectedFields: ["etag", "status"])
    let request = try #require(fake.requests.first)
    #expect(request.path == "/bigquery/v2/projects/other/jobs")
    #expect(request.queryValue("fields") == "jobReference,configuration,etag,status")
    let configuration = try request.jsonBody()["configuration"] as? [String: Any]
    let copy = configuration?["copy"] as? [String: Any]
    let sources = copy?["sourceTables"] as? [[String: Any]]
    #expect(sources?.first?["projectId"] as? String == "other")
  }

  // Baseline: U.BigQueryImpl.38
  @Test func conflictOnFirstAttemptIsAnError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 409, reasons: ["duplicate"], message: "Already Exists: Job p:j")
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().createJob(self.copy, id: JobID(jobID: "j"))
    }
    #expect(error?.kind == .service)
    #expect(error?.httpStatusCode == 409)
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryImpl.39
  // Design: §5.2
  @Test func conflictAfterRetryRecoversTheGeneratedJob() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueueError(status: 503)
    fake.enqueueError(status: 409, reasons: ["duplicate"])
    fake.enqueue(json: JobFixtures.job(id: "recovered"))
    let job = try await fake.client().createJob(self.copy)
    #expect(job.id.jobID == "recovered")
    #expect(fake.requests.map(\.method) == [.post, .post, .get])
    let sent = try #require(try self.jobReference(fake.requests[0])["jobId"] as? String)
    #expect(fake.requests[2].path == "/bigquery/v2/projects/test-project/jobs/\(sent)")
  }

  // Baseline: U.BigQueryImpl.40
  // Design: §5.2
  @Test func conflictAfterRetryRecoversTheCallerJob() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(.error(URLError(.networkConnectionLost)))
    fake.enqueueError(status: 409, reasons: ["duplicate"], message: "Already Exists: Job")
    fake.enqueue(json: JobFixtures.job(id: "j"))
    let job = try await fake.client().createJob(self.copy, id: JobID(jobID: "j"))
    #expect(job.id.jobID == "j")
    #expect(fake.requests[2].path == "/bigquery/v2/projects/test-project/jobs/j")
  }

  // Design: §5.2
  @Test func jobRateLimitWithGeneratedIDRetriesWithFreshID() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "first", errorReason: "jobRateLimitExceeded"))
    fake.enqueue(json: JobFixtures.job(id: "second"))
    let job = try await fake.client().createJob(self.copy)
    #expect(job.status.errorResult == nil)
    let ids = try fake.requests.map { try self.jobReference($0)["jobId"] as? String }
    #expect(ids.count == 2)
    #expect(ids[0] != ids[1])
  }

  // Design: §5.2
  @Test func jobRateLimitWithCallerIDReturnsTheFailedJob() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "j", errorReason: "rateLimitExceeded"))
    let job = try await fake.client().createJob(self.copy, id: JobID(jobID: "j"))
    #expect(job.status.errorResult?.reason == "rateLimitExceeded")
    #expect(fake.requests.count == 1)
  }

  // Baseline: U.BigQueryImpl.41
  // Design: §5.3
  @Test func deleteJobSendsLocationAndMapsNotFound() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(status: 204, json: "")
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let client = fake.client()
    #expect(try await client.deleteJob(JobID(jobID: "j", location: "EU")))
    #expect(try await !client.deleteJob(JobID(jobID: "j", location: "EU")))
    let request = try #require(fake.requests.first)
    #expect(request.method == .delete)
    #expect(request.path == "/bigquery/v2/projects/test-project/jobs/j/delete")
    #expect(request.queryValue("location") == "EU")
  }

  // Baseline: U.BigQueryImpl.42, U.Job.02
  @Test func getJobUsesTheJobOrClientLocationAndProject() async throws {
    let fake = FakeHTTPTransport()
    for _ in 0..<3 { fake.enqueue(json: JobFixtures.job()) }
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let client = fake.client(location: "US")
    _ = try await client.getJob(JobID(jobID: "j"))
    _ = try await client.getJob(JobID(jobID: "j", location: "EU"))
    _ = try await client.getJob(JobID(projectID: "other", jobID: "j"))
    let missing = try await client.getJob(JobID(jobID: "gone"))
    #expect(missing == nil)
    let requests = fake.requests
    #expect(requests[0].path == "/bigquery/v2/projects/test-project/jobs/j")
    #expect(requests[0].queryValue("location") == "US")
    #expect(requests[1].queryValue("location") == "EU")
    #expect(requests[2].path == "/bigquery/v2/projects/other/jobs/j")
    #expect(requests[0].queryValue("fields") == nil)
  }

  // Baseline: U.Job.03
  @Test func getJobReportsStateWithSelectedFields() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "DONE"))
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    let client = fake.client()
    let done = try await client.getJob(JobID(jobID: "j"), selectedFields: ["status"])
    let running = try await client.getJob(JobID(jobID: "j"), selectedFields: ["status"])
    #expect(done?.status.isDone == true)
    #expect(running?.status.isDone == false)
    #expect(fake.requests[0].queryValue("fields") == "jobReference,configuration,status")
  }

  // Baseline: U.BigQueryImpl.43
  @Test func listJobsPagesAndSendsOptions() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"""
        {"nextPageToken": "t2", "jobs": [
          {"jobReference": {"projectId": "p", "jobId": "a"}, "state": "DONE",
           "configuration": {"query": {"query": "SELECT 1"}}, "user_email": "me@example.com"}]}
        """#)
    fake.enqueue(
      json: #"""
        {"jobs": [{"jobReference": {"projectId": "p", "jobId": "b"}, "state": "RUNNING"}]}
        """#)
    let jobs = try await fake.client().listJobs(
      projectID: "p", allUsers: true, stateFilter: [.done, .running],
      parentJob: JobID(jobID: "parent"),
      minCreationTime: Date(timeIntervalSince1970: 1),
      maxCreationTime: Date(timeIntervalSince1970: 2),
      pageSize: 1
    ).collect()
    #expect(jobs.map(\.id.jobID) == ["a", "b"])
    #expect(jobs.map(\.status.state) == [.done, .running])
    #expect(jobs[0].userEmail == "me@example.com")
    guard case .query(let query) = jobs[0].configuration else {
      Issue.record("expected a query configuration")
      return
    }
    #expect(query.query == "SELECT 1")
    let first = fake.requests[0]
    #expect(first.path == "/bigquery/v2/projects/p/jobs")
    #expect(first.queryValue("projection") == "full")
    #expect(first.queryValue("allUsers") == "true")
    #expect(first.query.filter { $0.name == "stateFilter" }.map(\.value) == ["done", "running"])
    #expect(first.queryValue("parentJobId") == "parent")
    #expect(first.queryValue("minCreationTime") == "1000")
    #expect(first.queryValue("maxCreationTime") == "2000")
    #expect(first.queryValue("maxResults") == "1")
    #expect(first.queryValue("pageToken") == nil)
    #expect(fake.requests[1].queryValue("pageToken") == "t2")
  }

  // Baseline: U.BigQueryImpl.44
  @Test func listJobsFieldsMaskWrapsJobs() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: #"""
        {"jobs": [{"jobReference": {"projectId": "p", "jobId": "a"}, "state": "DONE",
                   "errorResult": {"reason": "invalidQuery"}, "statistics": {"creationTime": "5"}}]}
        """#)
    let jobs = try await fake.client().listJobs(selectedFields: ["statistics"], pageToken: "start")
      .collect()
    #expect(jobs.first?.status.errorResult?.reason == "invalidQuery")
    #expect(jobs.first?.statistics?.creationTime == Date(timeIntervalSince1970: 0.005))
    #expect(
      fake.requests[0].queryValue("fields")
        == "nextPageToken,jobs(jobReference,configuration,state,errorResult,statistics)")
    #expect(fake.requests[0].queryValue("pageToken") == "start")
  }

  // Baseline: U.BigQueryImpl.45, U.Job.10
  // Design: §5.3
  @Test func cancelJobPostsToTheJobAndMapsNotFound() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: #"{"job": {}}"#)
    fake.enqueue(json: #"{"job": {}}"#)
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let client = fake.client()
    #expect(try await client.cancelJob(JobID(jobID: "j")))
    #expect(try await client.cancelJob(JobID(projectID: "other", jobID: "j", location: "EU")))
    #expect(try await !client.cancelJob(JobID(jobID: "gone")))
    #expect(fake.requests[0].method == .post)
    #expect(fake.requests[0].path == "/bigquery/v2/projects/test-project/jobs/j/cancel")
    #expect(fake.requests[1].path == "/bigquery/v2/projects/other/jobs/j/cancel")
    #expect(fake.requests[1].queryValue("location") == "EU")
  }

  // Baseline: U.Job.04
  @Test func waitForJobPollsUntilDone() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "PENDING"))
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    fake.enqueue(json: JobFixtures.job(state: "DONE"))
    fake.enqueue(json: JobFixtures.job(state: "DONE", statistics: #"{"creationTime": "7"}"#))
    let job = try await fake.client().waitForJob(JobID(jobID: "j"))
    #expect(job.status.isDone)
    #expect(job.statistics?.creationTime != nil)
    #expect(fake.requests.count == 4)
    #expect(fake.requests[0].queryValue("fields") == "jobReference,configuration,status")
    #expect(fake.requests[3].queryValue("fields") == nil)
  }

  // Baseline: U.Job.10
  // Design: §6.3
  @Test func waitForJobThrowsTheJobError() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "DONE", errorReason: "invalid"))
    fake.enqueue(json: JobFixtures.job(state: "DONE", errorReason: "invalid"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().waitForJob(JobID(jobID: "j"))
    }
    #expect(error?.kind == .job)
    #expect(error?.reason == "invalid")
    #expect(error?.jobID?.jobID == "j")
  }

  // Baseline: U.Job.07
  // Design: §5.3
  @Test func waitForJobThrowsNotFoundWhenTheJobDisappears() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    fake.enqueueError(status: 404, reasons: ["notFound"])
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().waitForJob(JobID(jobID: "j"))
    }
    #expect(error?.isNotFound == true)
  }

  // Baseline: U.Job.08
  @Test func waitForJobTimesOutWithoutCancelling() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(state: "RUNNING"))
    let error = await #expect(throws: BigQueryError.self) {
      _ = try await fake.client().waitForJob(JobID(jobID: "j"), timeout: .zero)
    }
    #expect(error?.kind == .timeout)
    #expect(error?.jobID == JobID(projectID: "test-project", jobID: "j"))
    #expect(fake.requests.allSatisfy { $0.method == .get })
  }

  // Design: §10
  @Test func runJobCreatesAndWaitsUntilDone() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "j", state: "RUNNING"))
    fake.enqueue(json: JobFixtures.job(id: "j", state: "RUNNING"))
    fake.enqueue(json: JobFixtures.job(id: "j", state: "DONE"))
    fake.enqueue(
      json: JobFixtures.job(id: "j", state: "DONE", statistics: #"{"totalSlotMs": "42"}"#))
    let job = try await fake.client().runJob(
      .query(QueryJobConfiguration("SELECT 1")), id: JobID(jobID: "j"))
    #expect(job.id == JobID(projectID: "test-project", jobID: "j"))
    #expect(job.status.state == .done)
    #expect(job.statistics?.totalSlotMs == 42)
    #expect(fake.requests.map(\.method) == [.post, .get, .get, .get])
  }

  // Design: §10
  @Test func runJobReturnsImmediatelyWhenCreatedJobIsAlreadyDone() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(
      json: JobFixtures.job(id: "j", state: "DONE", statistics: #"{"totalSlotMs": "42"}"#))
    let job = try await fake.client().runJob(
      .query(QueryJobConfiguration("SELECT 1")), id: JobID(jobID: "j"))
    #expect(job.id == JobID(projectID: "test-project", jobID: "j"))
    #expect(job.status.state == .done)
    #expect(job.statistics?.totalSlotMs == 42)
    #expect(fake.requests.count == 1)
  }

  // Design: §10
  @Test func runJobThrowsWhenCreatedJobAlreadyFailed() async throws {
    let fake = FakeHTTPTransport()
    fake.enqueue(json: JobFixtures.job(id: "j", state: "DONE", errorReason: "invalid"))
    let error = await #expect(throws: BigQueryError.self) {
      try await fake.client().runJob(
        .query(QueryJobConfiguration("SELECT 1")), id: JobID(jobID: "j"))
    }
    #expect(error?.kind == .job)
    #expect(error?.reason == "invalid")
    #expect(fake.requests.count == 1)
  }
}
