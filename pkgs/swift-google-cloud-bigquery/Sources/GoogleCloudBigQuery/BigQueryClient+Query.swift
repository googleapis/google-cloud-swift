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
public import GoogleGax

extension BigQueryClient {
  /// Runs a query and returns its result once it completes.
  ///
  /// ```swift
  /// let result = try await client.query(
  ///   "SELECT name FROM dataset.people WHERE age > @age", parameters: .named(["age": .int64(21)]))
  /// for try await row in result.rows {
  ///   print(row["name"] ?? .null)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - sql: the GoogleSQL query text.
  ///   - parameters: the query parameters, if any.
  ///   - pageSize: the maximum number of rows in each page of ``QueryResult/rows``, or `nil` for
  ///     the service default. Sets ``QueryJobConfiguration/maxResults``.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/job`` if the service
  ///   rejects the query or the query fails; see
  ///   ``query(_:jobID:projectID:location:timeout:options:)``.
  public func query(
    _ sql: String,
    parameters: QueryParameters? = nil,
    pageSize: Int? = nil,
    options: RequestOptions = .init()
  ) async throws -> QueryResult {
    var configuration = QueryJobConfiguration(sql, parameters: parameters)
    configuration.maxResults = pageSize.map(Int64.init)
    return try await self.query(configuration, options: options)
  }

  /// Runs a query and returns its result once it completes.
  ///
  /// Simple queries run through the `jobs.query` API, which may return the results in a single
  /// round trip and, with ``JobCreationMode/optional``, without creating a job. Queries that set
  /// options `jobs.query` does not support, such as a destination table, run as a query job.
  ///
  /// - Parameters:
  ///   - configuration: the query. ``QueryJobConfiguration/dryRun`` must be `false`; use
  ///     ``dryRun(_:projectID:location:options:)`` instead.
  ///   - jobID: the ID of the query job. Setting it always creates a job with exactly this ID.
  ///   - projectID: the project that runs the query, or `nil` for the client project. Ignored
  ///     when `jobID` is set.
  ///   - location: the location that runs the query, or `nil` for the client location. Ignored
  ///     when `jobID` is set.
  ///   - timeout: how long to wait for the query to complete, or `nil` to wait as long as it
  ///     runs. The query is not cancelled when the timeout expires.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/job`` if the query
  ///   fails, ``BigQueryError/Kind-swift.struct/timeout`` if `timeout` expires first, or
  ///   ``BigQueryError/Kind-swift.struct/invalidArgument`` for a dry run. A query fails when the
  ///   service rejects it, for example for a syntax error or a missing table (HTTP 400, 403, 404
  ///   or 409, with ``BigQueryError/httpStatusCode`` set), or when its job fails, for example
  ///   with a runtime `ERROR()`. Either way the kind is the same, whether or not a job ran, so
  ///   match on ``BigQueryError/reason`` or ``BigQueryError/isNotFound`` for the cause.
  ///   Authentication failures (401) and exhausted retries keep kind
  ///   ``BigQueryError/Kind-swift.struct/service``.
  public func query(
    _ configuration: QueryJobConfiguration,
    jobID: JobID? = nil,
    projectID: String? = nil,
    location: String? = nil,
    timeout: Duration? = nil,
    options: RequestOptions = .init()
  ) async throws -> QueryResult {
    guard !configuration.dryRun else {
      throw BigQueryError.invalidArgument("query() does not run dry runs; use dryRun() instead")
    }
    let deadline = timeout.map { ContinuousClock.now + $0 }
    if jobID == nil && configuration.isFastPathEligible {
      return try await self.fastQuery(
        configuration, projectID: projectID ?? self.projectID, location: location ?? self.location,
        timeout: timeout, deadline: deadline, options: options)
    }
    let id = self.resolve(jobID ?? JobID.random(projectID: projectID, location: location))
    let job: Job
    do {
      job = try await self.insertJob(
        .query(configuration), id: id, generatedID: jobID == nil, selectedFields: nil,
        options: options)
    } catch let error as BigQueryError {
      throw Self.queryFailure(error, job: id)
    }
    if let failure = job.failure { throw failure }
    return try await self.completedQuery(
      job.id, pageSize: configuration.maxResults, startIndex: nil, deadline: deadline,
      options: options)
  }

  /// Waits for a query job to complete and returns its result.
  ///
  /// - Parameters:
  ///   - job: the query job. A `nil` project or location uses the client's.
  ///   - startIndex: the zero-based index of the first row to return.
  ///   - pageSize: the maximum number of rows in each page.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/job`` if the query
  ///   failed.
  public func getQueryResults(
    _ job: JobID,
    startIndex: UInt64? = nil,
    pageSize: Int? = nil,
    options: RequestOptions = .init()
  ) async throws -> QueryResult {
    try await self.completedQuery(
      self.resolve(job), pageSize: pageSize.map(Int64.init), startIndex: startIndex, deadline: nil,
      options: options)
  }

  /// Validates a query and estimates its cost without running it.
  ///
  /// ```swift
  /// let estimate = try await client.dryRun(
  ///   "SELECT * FROM dataset.people WHERE age > @age", parameters: .named(["age": .int64(21)]))
  /// print(estimate.totalBytesProcessed ?? 0)
  /// ```
  ///
  /// - Parameters:
  ///   - sql: the GoogleSQL query text.
  ///   - parameters: the query parameters, if any.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/service`` if the
  ///   query is invalid.
  public func dryRun(
    _ sql: String,
    parameters: QueryParameters? = nil,
    options: RequestOptions = .init()
  ) async throws -> QueryDryRunResult {
    try await self.dryRun(QueryJobConfiguration(sql, parameters: parameters), options: options)
  }

  /// Validates a query and estimates its cost without running it.
  ///
  /// ```swift
  /// let estimate = try await client.dryRun(QueryJobConfiguration("SELECT * FROM dataset.t"))
  /// print(estimate.totalBytesProcessed ?? 0)
  /// ```
  ///
  /// - Parameters:
  ///   - configuration: the query. ``QueryJobConfiguration/dryRun`` is ignored.
  ///   - projectID: the project that would run the query, or `nil` for the client project.
  ///   - location: the location that would run the query, or `nil` for the client location.
  ///   - options: per-call options.
  /// - Throws: ``BigQueryError`` with kind ``BigQueryError/Kind-swift.struct/service`` if the
  ///   query is invalid.
  public func dryRun(
    _ configuration: QueryJobConfiguration,
    projectID: String? = nil,
    location: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> QueryDryRunResult {
    var configuration = configuration
    configuration.dryRun = true
    let job = try await self.insertJob(
      .query(configuration),
      id: self.resolve(JobID.random(projectID: projectID, location: location)),
      generatedID: true, selectedFields: nil, options: options)
    if let failure = job.failure { throw failure }
    let statistics = job.statistics?.query
    return QueryDryRunResult(
      schema: statistics?.schema,
      totalBytesProcessed: statistics?.totalBytesProcessed ?? job.statistics?.totalBytesProcessed,
      referencedTables: statistics?.referencedTables ?? [],
      undeclaredParameters: statistics?.undeclaredQueryParameters ?? [],
      statementType: statistics?.statementType,
      statistics: statistics)
  }
}

// MARK: - Query paths

extension BigQueryClient {
  /// How long each `getQueryResults` call asks the service to wait for the query to complete.
  static let queryPollInterval: Duration = .seconds(10)

  /// The HTTP statuses of a `jobs.query` or `jobs.insert` response that reject the query itself.
  static let queryRejectionStatusCodes: Set<Int> = [400, 403, 404, 409]

  /// Reports `error`, thrown by the `jobs.query` or `jobs.insert` request of a query, as a
  /// ``BigQueryError/Kind-swift.struct/job`` error if the service rejected the query, so that
  /// the kind does not depend on whether the query ran as a job. Transport failures, such as
  /// exhausted retries, are returned unchanged.
  static func queryFailure(_ error: BigQueryError, job: JobID?) -> BigQueryError {
    guard error.kind == .service,
      let status = error.httpStatusCode, Self.queryRejectionStatusCodes.contains(status),
      !error.errors.contains(where: {
        $0.reason.map(BigQueryRetryErrors.retryableReasons.contains) ?? false
      })
    else { return error }
    var failure = error
    failure.kind = .job
    failure.jobID = error.jobID ?? job
    return failure
  }

  /// Runs a query through `jobs.query` (design §6.1).
  private func fastQuery(
    _ configuration: QueryJobConfiguration,
    projectID: String,
    location: String?,
    timeout: Duration?,
    deadline: ContinuousClock.Instant?,
    options: RequestOptions
  ) async throws -> QueryResult {
    var requestID = UUID().uuidString
    let jobCreationMode = configuration.jobCreationMode ?? self.defaultJobCreationMode
    let response: WireQueryResponse
    do {
      response = try await self.transport.json(
        idempotent: true, options: options,
        request: { _ in
          let body = configuration.queryRequest(
            requestID: requestID, location: location, jobCreationMode: jobCreationMode,
            timeout: timeout, defaultProject: projectID)
          return HTTPRequest(
            method: .post,
            path: "/bigquery/v2/projects/\(HTTPRequest.encode(segment: projectID))/queries",
            body: try RequestBody.json(body), options: options)
        },
        validate: { (response: WireQueryResponse) in
          let errors = response.errors ?? []
          guard errors.contains(where: Self.isJobRateLimit) else { return }
          // The service deduplicates on `requestId`, so a retry must use a new one.
          requestID = UUID().uuidString
          throw RequestError.jobRateLimited(errors)
        })
    } catch let error as BigQueryError {
      throw Self.queryFailure(error, job: nil)
    }
    let jobID = response.jobReference.map(JobID.init(wire:))
    if let failure = BigQueryError(job: jobID, errorResult: nil, errors: response.errors ?? []) {
      throw failure
    }
    if response.jobComplete != true {
      guard let jobID else {
        throw RequestError.malformedResponse("incomplete jobs.query response without a job")
      }
      // The query is still running: continue like a query job.
      var result = try await self.completedQuery(
        jobID, pageSize: configuration.maxResults, startIndex: nil, deadline: deadline,
        options: options)
      result.jobCreationReason = response.jobCreationReason.flatMap {
        specifiedEnumValue($0.code.stringValue)
      }
      return result
    }
    var final = QueryPage(response)
    if response.schema == nil, let jobID {
      // DDL statements and some scripts: the result set, if any, comes from getQueryResults.
      final = QueryPage(
        try await self.queryResultsPage(
          jobID, pageToken: nil, startIndex: nil, pageSize: configuration.maxResults,
          timeout: nil, options: options))
    }
    return QueryResult(
      schema: final.schema,
      totalRows: final.totalRows,
      numDMLAffectedRows: response.numDmlAffectedRows,
      dmlStats: response.dmlStats.map(DMLStats.init(wire:)),
      jobID: jobID,
      queryID: response.queryId?.nonEmpty,
      location: response.location?.nonEmpty ?? jobID?.location,
      cacheHit: response.cacheHit,
      statementType: response.statementType?.nonEmpty.map(StatementType.init(rawValue:)),
      jobCreationReason: response.jobCreationReason.flatMap {
        specifiedEnumValue($0.code.stringValue)
      },
      totalBytesProcessed: response.totalBytesProcessed,
      totalBytesBilled: response.totalBytesBilled,
      totalSlotMs: response.totalSlotMs,
      sessionInfo: response.sessionInfo.map(SessionInfo.init(wire:)),
      creationTime: response.creationTime.flatMap(Date.init(millisecondsSinceEpoch:)),
      startTime: response.startTime.flatMap(Date.init(millisecondsSinceEpoch:)),
      endTime: response.endTime.flatMap(Date.init(millisecondsSinceEpoch:)),
      rows: try self.rowSequence(
        final, jobID: final.pageToken == nil ? nil : jobID, pageSize: configuration.maxResults,
        options: options))
  }

  /// Waits for the query job `id` to complete, then returns its result with statistics from
  /// `jobs.get`.
  private func completedQuery(
    _ id: JobID,
    pageSize: Int64?,
    startIndex: UInt64?,
    deadline: ContinuousClock.Instant?,
    options: RequestOptions
  ) async throws -> QueryResult {
    let page = QueryPage(
      try await self.waitForQueryResults(
        id, pageSize: pageSize, startIndex: startIndex, deadline: deadline, options: options))
    guard let job = try await self.getJob(id, options: options) else {
      throw Self.jobNotFound(id)
    }
    if let failure = job.failure { throw failure }
    let statistics = job.statistics
    let query = statistics?.query
    return QueryResult(
      schema: page.schema ?? query?.schema,
      totalRows: page.totalRows,
      numDMLAffectedRows: query?.numDMLAffectedRows ?? page.numDMLAffectedRows,
      dmlStats: query?.dmlStats,
      jobID: job.id,
      location: job.id.location,
      cacheHit: query?.cacheHit ?? page.cacheHit,
      statementType: query?.statementType,
      totalBytesProcessed: query?.totalBytesProcessed ?? statistics?.totalBytesProcessed,
      totalBytesBilled: query?.totalBytesBilled,
      totalSlotMs: query?.totalSlotMs ?? statistics?.totalSlotMs,
      sessionInfo: statistics?.sessionInfo,
      creationTime: statistics?.creationTime,
      startTime: statistics?.startTime,
      endTime: statistics?.endTime,
      rows: try self.rowSequence(page, jobID: id, pageSize: pageSize, options: options))
  }

  /// Long-polls `getQueryResults` until the query completes, and returns the first page.
  private func waitForQueryResults(
    _ id: JobID,
    pageSize: Int64?,
    startIndex: UInt64?,
    deadline: ContinuousClock.Instant?,
    options: RequestOptions
  ) async throws -> WireGetQueryResultsResponse {
    while true {
      var wait = Self.queryPollInterval
      if let deadline {
        let remaining = deadline - ContinuousClock.now
        guard remaining > .zero else { throw Self.waitTimeout(id) }
        wait = min(wait, remaining)
      }
      let response: WireGetQueryResultsResponse
      do {
        response = try await self.queryResultsPage(
          id, pageToken: nil, startIndex: startIndex, pageSize: pageSize, timeout: wait,
          options: options)
      } catch let error as BigQueryError where error.kind == .service {
        // A failed query makes getQueryResults fail; report the job's own error instead.
        if let job = try? await self.getJob(id, options: options), let failure = job.failure {
          throw failure
        }
        throw error
      }
      if let failure = BigQueryError(job: id, errorResult: nil, errors: response.errors ?? []) {
        throw failure
      }
      if response.jobComplete == true { return response }
    }
  }

  /// Sends one `getQueryResults` request.
  private func queryResultsPage(
    _ id: JobID,
    pageToken: String?,
    startIndex: UInt64?,
    pageSize: Int64?,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> WireGetQueryResultsResponse {
    var query = Self.locationQuery(id)
    query.append(RowFormat.queryItem)
    if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
    if let startIndex { query.append(URLQueryItem(name: "startIndex", value: String(startIndex))) }
    if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
    if let timeout {
      query.append(URLQueryItem(name: "timeoutMs", value: String(timeout.wholeMilliseconds)))
    }
    let path =
      "/bigquery/v2/projects/\(HTTPRequest.encode(segment: id.projectID ?? self.projectID))"
      + "/queries/\(HTTPRequest.encode(segment: id.jobID))"
    return try await self.transport.json(
      HTTPRequest(method: .get, path: path, query: query, options: options), idempotent: true)
  }

  /// The rows of a result, starting with `first`. Later pages come from `getQueryResults` on
  /// `jobID`; a `nil` `jobID` means there are no later pages.
  ///
  /// - Throws: `RequestError.malformedResponse` if `first` has more pages but there is no job to
  ///   read them from. The service creates a job for results larger than one page.
  private func rowSequence(
    _ first: QueryPage, jobID: JobID?, pageSize: Int64?, options: RequestOptions
  ) throws -> RowSequence {
    guard let schema = first.schema else {
      return RowSequence(schema: Schema([]), totalRows: first.totalRows, rows: PagedSequence([]))
    }
    if jobID == nil && first.pageToken != nil {
      throw RequestError.malformedResponse("query results have more pages but no job reference")
    }
    let firstPage = Page(
      items: try Row.rows(from: first.rows, schema: schema),
      nextPageToken: first.pageToken)
    return RowSequence(
      schema: schema, totalRows: first.totalRows,
      rows: PagedSequence(firstPage: firstPage) { token in
        guard let jobID, let token else { return Page(items: []) }
        let response = try await self.queryResultsPage(
          jobID, pageToken: token, startIndex: nil, pageSize: pageSize, timeout: nil,
          options: options)
        return Page(
          items: try Row.rows(from: response.rows ?? [], schema: schema),
          nextPageToken: response.pageToken?.nonEmpty)
      })
  }
}

/// Wire representation of `jobs.query` that decodes `rows` directly as `[WireRow]` instead of
/// `[GoogleWKT.WKTStruct]`.
private struct WireQueryResponse: Decodable, Sendable {
  var schema: GoogleCloudBigQueryV2.TableSchema?
  var jobReference: GoogleCloudBigQueryV2.JobReference?
  var jobCreationReason: GoogleCloudBigQueryV2.JobCreationReason?
  var queryId: String?
  var location: String?
  var totalRows: UInt64?
  var pageToken: String?
  var rows: [WireRow]?
  var totalBytesProcessed: Int64?
  var totalBytesBilled: Int64?
  var totalSlotMs: Int64?
  var jobComplete: Bool?
  var errors: [GoogleCloudBigQueryV2.ErrorProto]?
  var cacheHit: Bool?
  var numDmlAffectedRows: Int64?
  var sessionInfo: GoogleCloudBigQueryV2.SessionInfo?
  var dmlStats: GoogleCloudBigQueryV2.DmlStats?
  var creationTime: Int64?
  var startTime: Int64?
  var endTime: Int64?
  var statementType: String?
}

/// Wire representation of `jobs.getQueryResults` that decodes `rows` directly as `[WireRow]`
/// instead of `[GoogleWKT.WKTStruct]`.
private struct WireGetQueryResultsResponse: Decodable, Sendable {
  var schema: GoogleCloudBigQueryV2.TableSchema?
  var jobReference: GoogleCloudBigQueryV2.JobReference?
  var totalRows: UInt64?
  var pageToken: String?
  var rows: [WireRow]?
  var totalBytesProcessed: Int64?
  var jobComplete: Bool?
  var errors: [GoogleCloudBigQueryV2.ErrorProto]?
  var cacheHit: Bool?
  var numDmlAffectedRows: Int64?
}

/// The parts of a `jobs.query` or `getQueryResults` response that describe a page of results.
private struct QueryPage {
  var schema: Schema?
  var totalRows: UInt64?
  var rows: [WireRow]
  var pageToken: String?
  var numDMLAffectedRows: Int64?
  var cacheHit: Bool?

  init(_ response: WireQueryResponse) {
    self.schema = response.schema.map(Schema.init(wire:))
    self.totalRows = response.totalRows
    self.rows = response.rows ?? []
    self.pageToken = response.pageToken?.nonEmpty
    self.numDMLAffectedRows = response.numDmlAffectedRows
    self.cacheHit = response.cacheHit
  }

  init(_ response: WireGetQueryResultsResponse) {
    self.schema = response.schema.map(Schema.init(wire:))
    self.totalRows = response.totalRows
    self.rows = response.rows ?? []
    self.pageToken = response.pageToken?.nonEmpty
    self.numDMLAffectedRows = response.numDmlAffectedRows
    self.cacheHit = response.cacheHit
  }
}
