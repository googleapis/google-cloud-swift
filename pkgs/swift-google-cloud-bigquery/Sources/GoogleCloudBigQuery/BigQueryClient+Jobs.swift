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

public import Foundation
import GoogleCloudBigQueryV2
public import GoogleGax

extension BigQueryClient {
  /// Creates a job and returns it without waiting for it to finish.
  ///
  /// ```swift
  /// let job = try await client.createJob(.query(QueryJobConfiguration("SELECT 1")))
  /// let finished = try await client.waitForJob(job.id)
  /// ```
  ///
  /// When `id` is `nil` the client generates a job ID, which makes the request safe to retry. If
  /// the service reports a job-level rate limit, the client retries with a new generated ID.
  ///
  /// With a caller-supplied `id`, a job that the service rejects with a rate-limit error is
  /// returned as is: check ``JobStatus/errorResult``, or call ``waitForJob(_:timeout:options:)``,
  /// which throws it.
  ///
  /// - Parameters:
  ///   - configuration: what the job does. Tables and datasets without a project use the job's
  ///     project.
  ///   - id: the job ID, or `nil` to generate one. A `nil` project or location uses the client's.
  ///   - selectedFields: the job fields to return, for example `["status"]`. `jobReference` and
  ///     `configuration` are always returned. `nil` returns every field.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/service`` and HTTP
  ///   status 409 if a job with the caller-supplied `id` already exists.
  public func createJob(
    _ configuration: JobConfiguration,
    id: JobID? = nil,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Job {
    try await self.insertJob(
      configuration, id: self.resolve(id ?? JobID.random()), generatedID: id == nil,
      selectedFields: selectedFields, options: options)
  }

  /// Returns a job, or `nil` if it does not exist.
  ///
  /// A job that failed is returned, not thrown: check ``JobStatus/errorResult``.
  ///
  /// - Parameters:
  ///   - id: the job. A `nil` project or location uses the client's.
  ///   - selectedFields: the job fields to return, for example `["status"]`. `jobReference` and
  ///     `configuration` are always returned. `nil` returns every field.
  ///   - options: per-call options.
  public func getJob(
    _ id: JobID,
    selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Job? {
    let id = self.resolve(id)
    let wire = try await self.transport.jsonOrNil(
      HTTPRequest(
        method: .get, path: Self.jobPath(id),
        query: Self.locationQuery(id) + Self.jobFieldsQuery(selectedFields), options: options),
      as: GoogleCloudBigQueryV2.Job.self)
    return wire.map(Job.init(wire:))
  }

  /// Lists the jobs of a project, most recent first.
  ///
  /// ```swift
  /// for try await job in client.listJobs(stateFilter: [.running]) {
  ///   print(job.id)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - projectID: the project, or `nil` for the client project.
  ///   - allUsers: whether to list the jobs of every user. Requires the project owner role.
  ///   - stateFilter: list only jobs in these states. Empty lists jobs in every state.
  ///   - parentJob: list only the child jobs of this script job.
  ///   - minCreationTime: list only jobs created at or after this time.
  ///   - maxCreationTime: list only jobs created at or before this time.
  ///   - selectedFields: the job fields to return, for example `["statistics"]`.
  ///     `jobReference`, `configuration`, `state`, and `errorResult` are always returned. `nil`
  ///     returns every field.
  ///   - pageSize: the maximum number of jobs in each page.
  ///   - pageToken: the page to start from, from ``Page/nextPageToken``.
  ///   - options: per-call options.
  public func listJobs(
    projectID: String? = nil,
    allUsers: Bool = false,
    stateFilter: Set<JobState> = [],
    parentJob: JobID? = nil,
    minCreationTime: Date? = nil,
    maxCreationTime: Date? = nil,
    selectedFields: [String]? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Job> {
    let projectID = projectID ?? self.projectID
    var query = [URLQueryItem(name: "projection", value: "full")]
    if allUsers { query.append(URLQueryItem(name: "allUsers", value: "true")) }
    for state in stateFilter.map({ $0.rawValue.lowercased() }).sorted() {
      query.append(URLQueryItem(name: "stateFilter", value: state))
    }
    if let parentJob {
      query.append(URLQueryItem(name: "parentJobId", value: parentJob.jobID))
    }
    if let minCreationTime {
      query.append(
        URLQueryItem(name: "minCreationTime", value: String(minCreationTime.millisecondsSinceEpoch))
      )
    }
    if let maxCreationTime {
      query.append(
        URLQueryItem(name: "maxCreationTime", value: String(maxCreationTime.millisecondsSinceEpoch))
      )
    }
    if let selectedFields {
      let fields = Self.union(
        ["jobReference", "configuration", "state", "errorResult"], selectedFields)
      query.append(URLQueryItem(name: "fields", value: "nextPageToken,jobs(\(fields))"))
    }
    if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
    let firstQuery = query
    return PagedSequence { token in
      var query = firstQuery
      if let token = token ?? pageToken {
        query.append(URLQueryItem(name: "pageToken", value: token))
      }
      let list: GoogleCloudBigQueryV2.JobList = try await self.transport.json(
        HTTPRequest(
          method: .get, path: Self.jobsPath(projectID), query: query, options: options),
        idempotent: true)
      return Page(items: list.jobs.map(Job.init(wire:)), nextPageToken: list.nextPageToken.nonEmpty)
    }
  }

  /// Requests cancellation of a job. Returns `false` if the job does not exist.
  ///
  /// Cancellation is asynchronous: the job may still finish, successfully or not. Use
  /// ``waitForJob(_:timeout:options:)`` to wait for it to stop.
  @discardableResult
  public func cancelJob(_ id: JobID, options: RequestOptions = .init()) async throws -> Bool {
    let id = self.resolve(id)
    return try await self.transport.deleteOrFalse(
      HTTPRequest(
        method: .post, path: Self.jobPath(id) + "/cancel", query: Self.locationQuery(id),
        options: options))
  }

  /// Deletes the metadata of a finished job. Returns `false` if the job does not exist.
  ///
  /// A retried request whose first attempt succeeded but lost its response also returns
  /// `false`.
  @discardableResult
  public func deleteJob(_ id: JobID, options: RequestOptions = .init()) async throws -> Bool {
    let id = self.resolve(id)
    return try await self.transport.deleteOrFalse(
      HTTPRequest(
        method: .delete, path: Self.jobPath(id) + "/delete", query: Self.locationQuery(id),
        options: options))
  }

  /// Waits for a job to finish and returns it.
  ///
  /// The client polls the job using the polling backoff policy of the client or of `options`.
  ///
  /// - Parameters:
  ///   - id: the job. A `nil` project or location uses the client's.
  ///   - timeout: how long to wait, or `nil` to wait as long as the job runs. The job is not
  ///     cancelled when the timeout expires.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/job`` if the job
  ///   failed, ``BigQueryError/Kind-swift.struct/timeout`` if `timeout` expired first, or a
  ///   service error with ``BigQueryError/isNotFound`` if the job does not exist.
  public func waitForJob(
    _ id: JobID,
    timeout: Duration? = nil,
    options: RequestOptions = .init()
  ) async throws -> Job {
    let id = self.resolve(id)
    let deadline = timeout.map { ContinuousClock.now + $0 }
    let policy = options.pollingBackoffPolicy ?? self.transport.clientOptions.pollingBackoffPolicy
    var state = PollingState()
    while true {
      guard let polled = try await self.getJob(id, selectedFields: ["status"], options: options)
      else {
        throw Self.jobNotFound(id)
      }
      if polled.status.isDone {
        guard let job = try await self.getJob(id, options: options) else {
          throw Self.jobNotFound(id)
        }
        if let failure = job.failure { throw failure }
        return job
      }
      state.attemptCount += 1
      var delay = policy.backoffDelay(for: state)
      if let deadline {
        let remaining = deadline - ContinuousClock.now
        guard remaining > .zero else { throw Self.waitTimeout(id) }
        delay = min(delay, remaining)
      }
      try await self.transport.sleep(delay)
    }
  }
}

// MARK: - Internal helpers

extension BigQueryClient {
  /// Sends `jobs.insert` with a stable job ID (design §5.2).
  ///
  /// - A 2xx response whose job failed with a job-level rate limit is retried with a fresh ID
  ///   when `generatedID` is `true`, and returned as is otherwise.
  /// - A 409 is recovered with `jobs.get` only if an earlier attempt with the same ID was sent
  ///   in this call (a retry after a lost success).
  func insertJob(
    _ configuration: JobConfiguration,
    id: JobID,
    generatedID: Bool,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Job {
    var id = id
    var attemptsWithID = 0
    let query = Self.jobFieldsQuery(selectedFields)
    do {
      let wire: GoogleCloudBigQueryV2.Job = try await self.transport.json(
        idempotent: true, options: options,
        request: { _ in
          attemptsWithID += 1
          let body = GoogleCloudBigQueryV2.Job().with {
            $0.jobReference = id.wire
            $0.configuration = configuration.withDefaultProject(id.projectID ?? self.projectID).wire
          }
          return HTTPRequest(
            method: .post, path: Self.jobsPath(id.projectID ?? self.projectID), query: query,
            body: try RequestBody.json(body), options: options)
        },
        validate: { (job: GoogleCloudBigQueryV2.Job) in
          guard generatedID, let status = job.status, let error = status.errorResult,
            Self.isJobRateLimit(error)
          else { return }
          id = JobID.random(projectID: id.projectID, location: id.location)
          attemptsWithID = 0
          throw RequestError.jobRateLimited([error] + status.errors)
        })
      return Job(wire: wire)
    } catch let error as BigQueryError where error.httpStatusCode == 409 && attemptsWithID > 1 {
      if let job = try await self.getJob(id, selectedFields: selectedFields, options: options) {
        return job
      }
      throw error
    }
  }

  /// `true` for the errors that report a job-level rate limit.
  static func isJobRateLimit(_ error: GoogleCloudBigQueryV2.ErrorProto) -> Bool {
    error.reason == "rateLimitExceeded" || error.reason == "jobRateLimitExceeded"
  }

  static func jobsPath(_ projectID: String) -> String {
    "/bigquery/v2/projects/\(HTTPRequest.encode(segment: projectID))/jobs"
  }

  /// The path of a resolved job ID.
  static func jobPath(_ id: JobID) -> String {
    Self.jobsPath(id.projectID ?? "") + "/" + HTTPRequest.encode(segment: id.jobID)
  }

  /// The `location` query parameter of a resolved job ID, if it has a location.
  static func locationQuery(_ id: JobID) -> [URLQueryItem] {
    guard let location = id.location, !location.isEmpty else { return [] }
    return [URLQueryItem(name: "location", value: location)]
  }

  /// The `fields` query parameter of `jobs.get` and `jobs.insert`.
  static func jobFieldsQuery(_ selectedFields: [String]?) -> [URLQueryItem] {
    guard let selectedFields else { return [] }
    let fields = Self.union(["jobReference", "configuration"], selectedFields)
    return [URLQueryItem(name: "fields", value: fields)]
  }

  /// `required` followed by the entries of `fields` not already in it, comma-separated.
  private static func union(_ required: [String], _ fields: [String]) -> String {
    var all = required
    for field in fields where !all.contains(field) { all.append(field) }
    return all.joined(separator: ",")
  }

  static func jobNotFound(_ id: JobID) -> BigQueryError {
    BigQueryError(
      kind: .service, message: "Not found: Job \(id)", httpStatusCode: 404, status: "NOT_FOUND",
      errors: [BigQueryError.Detail(reason: "notFound", message: "Not found: Job \(id)")],
      jobID: id)
  }

  static func waitTimeout(_ id: JobID) -> BigQueryError {
    BigQueryError(
      kind: .timeout, message: "Timed out waiting for job \(id); the job is still running.",
      jobID: id)
  }
}
