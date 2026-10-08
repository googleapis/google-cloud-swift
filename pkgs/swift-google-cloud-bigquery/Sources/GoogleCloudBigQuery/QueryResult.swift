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

/// The result of a query: its rows, fetched lazily, and metadata about the query.
///
/// ```swift
/// let result = try await client.query("SELECT name, age FROM dataset.people")
/// for try await row in result.rows {
///   print(row["name"] ?? .null)
/// }
/// ```
///
/// For DML statements, ``numDMLAffectedRows`` reports the number of changed rows; ``totalRows``
/// only ever counts the rows of the result set.
public struct QueryResult: Sendable {
  /// The schema of the result, or `nil` if the query returned no result set, for example a DDL
  /// statement or some scripts.
  public var schema: Schema?

  /// The number of rows in the result set, or `nil` if the service did not report it.
  public var totalRows: UInt64?

  /// The number of rows inserted, updated, or deleted by a DML statement.
  public var numDMLAffectedRows: Int64?

  /// Detailed DML row counts.
  public var dmlStats: DMLStats?

  /// The job that ran the query, or `nil` if the service ran it without creating a job.
  public var jobID: JobID?

  /// The ID the service assigned to a query that ran without creating a job.
  public var queryID: String?

  /// The location where the query ran.
  public var location: String?

  /// Whether the result came from the query cache.
  public var cacheHit: Bool?

  /// The type of the statement, for example `SELECT` or `INSERT`.
  public var statementType: StatementType?

  /// Why the service created a job for a query with
  /// ``JobCreationMode/optional``, for example `LONG_RUNNING`.
  public var jobCreationReason: String?

  /// The number of bytes the query processed.
  public var totalBytesProcessed: Int64?

  /// The number of bytes billed for the query.
  public var totalBytesBilled: Int64?

  /// The slot-milliseconds the query consumed.
  public var totalSlotMs: Int64?

  /// The session the query ran in, if it created or joined one.
  public var sessionInfo: SessionInfo?

  /// When the query was created.
  public var creationTime: Date?

  /// When the query started running.
  public var startTime: Date?

  /// When the query finished.
  public var endTime: Date?

  /// The rows of the result set. Empty when ``schema`` is `nil`.
  public var rows: RowSequence

  /// Creates a query result, for example as a test double.
  public init(
    schema: Schema? = nil,
    totalRows: UInt64? = nil,
    numDMLAffectedRows: Int64? = nil,
    dmlStats: DMLStats? = nil,
    jobID: JobID? = nil,
    queryID: String? = nil,
    location: String? = nil,
    cacheHit: Bool? = nil,
    statementType: StatementType? = nil,
    jobCreationReason: String? = nil,
    totalBytesProcessed: Int64? = nil,
    totalBytesBilled: Int64? = nil,
    totalSlotMs: Int64? = nil,
    sessionInfo: SessionInfo? = nil,
    creationTime: Date? = nil,
    startTime: Date? = nil,
    endTime: Date? = nil,
    rows: RowSequence
  ) {
    self.schema = schema
    self.totalRows = totalRows
    self.numDMLAffectedRows = numDMLAffectedRows
    self.dmlStats = dmlStats
    self.jobID = jobID
    self.queryID = queryID
    self.location = location
    self.cacheHit = cacheHit
    self.statementType = statementType
    self.jobCreationReason = jobCreationReason
    self.totalBytesProcessed = totalBytesProcessed
    self.totalBytesBilled = totalBytesBilled
    self.totalSlotMs = totalSlotMs
    self.sessionInfo = sessionInfo
    self.creationTime = creationTime
    self.startTime = startTime
    self.endTime = endTime
    self.rows = rows
  }
}

/// What a query would do, reported by a dry run without running it.
public struct QueryDryRunResult: Sendable, Hashable {
  /// The schema the query would return, or `nil` if it returns no result set.
  public var schema: Schema?

  /// The number of bytes the query would process.
  public var totalBytesProcessed: Int64?

  /// The tables the query reads.
  public var referencedTables: [TableID]

  /// The parameters the query references but does not declare.
  public var undeclaredParameters: [UndeclaredQueryParameter]

  /// The type of the statement, for example `SELECT`.
  public var statementType: StatementType?

  /// All the query statistics the service reported.
  public var statistics: QueryStatistics?

  /// Creates a dry-run result, for example as a test double.
  public init(
    schema: Schema? = nil,
    totalBytesProcessed: Int64? = nil,
    referencedTables: [TableID] = [],
    undeclaredParameters: [UndeclaredQueryParameter] = [],
    statementType: StatementType? = nil,
    statistics: QueryStatistics? = nil
  ) {
    self.schema = schema
    self.totalBytesProcessed = totalBytesProcessed
    self.referencedTables = referencedTables
    self.undeclaredParameters = undeclaredParameters
    self.statementType = statementType
    self.statistics = statistics
  }
}
