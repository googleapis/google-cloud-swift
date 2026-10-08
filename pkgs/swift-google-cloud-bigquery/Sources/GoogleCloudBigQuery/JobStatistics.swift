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

/// Statistics about a job, reported by the service.
///
/// Every field is `nil` (or empty) when the service did not report it. Which fields are
/// reported depends on the job type and its state.
public struct JobStatistics: Sendable, Hashable {
  /// When the job was created.
  public var creationTime: Date?
  /// When the job started running.
  public var startTime: Date?
  /// When the job finished.
  public var endTime: Date?
  /// The total bytes processed by the job.
  public var totalBytesProcessed: Int64?
  /// The slot-milliseconds consumed by the job.
  public var totalSlotMs: Int64?
  /// The fraction of the job's work that is complete, from 0 to 1.
  public var completionRatio: Double?
  /// The number of child jobs, for a script.
  public var numChildJobs: Int64?
  /// The ID of the parent job, for a child job of a script.
  public var parentJobID: String?
  /// The reservation that ran the job.
  public var reservationID: String?
  /// Statistics for a child job of a script.
  public var scriptStatistics: ScriptStatistics?
  /// The transaction the job ran in, if any.
  public var transactionInfo: TransactionInfo?
  /// The session the job ran in, if any.
  public var sessionInfo: SessionInfo?
  /// Statistics specific to query jobs.
  public var query: QueryStatistics?
  /// Statistics specific to load jobs.
  public var load: LoadStatistics?
  /// Statistics specific to extract jobs.
  public var extract: ExtractStatistics?
  /// Statistics specific to copy jobs.
  public var copy: CopyStatistics?

  /// Creates job statistics, for example in a test double.
  public init(
    creationTime: Date? = nil, startTime: Date? = nil, endTime: Date? = nil,
    totalBytesProcessed: Int64? = nil, totalSlotMs: Int64? = nil, completionRatio: Double? = nil,
    numChildJobs: Int64? = nil, parentJobID: String? = nil, reservationID: String? = nil,
    scriptStatistics: ScriptStatistics? = nil, transactionInfo: TransactionInfo? = nil,
    sessionInfo: SessionInfo? = nil, query: QueryStatistics? = nil, load: LoadStatistics? = nil,
    extract: ExtractStatistics? = nil, copy: CopyStatistics? = nil
  ) {
    self.creationTime = creationTime
    self.startTime = startTime
    self.endTime = endTime
    self.totalBytesProcessed = totalBytesProcessed
    self.totalSlotMs = totalSlotMs
    self.completionRatio = completionRatio
    self.numChildJobs = numChildJobs
    self.parentJobID = parentJobID
    self.reservationID = reservationID
    self.scriptStatistics = scriptStatistics
    self.transactionInfo = transactionInfo
    self.sessionInfo = sessionInfo
    self.query = query
    self.load = load
    self.extract = extract
    self.copy = copy
  }
}

/// The session a query or load job ran in.
public struct SessionInfo: Sendable, Hashable {
  /// The session ID. Pass it as the `session_id` connection property to reuse the session.
  public var sessionID: String

  /// Creates session information.
  public init(sessionID: String) {
    self.sessionID = sessionID
  }
}

/// The multi-statement transaction a job ran in.
public struct TransactionInfo: Sendable, Hashable {
  /// The transaction ID.
  public var transactionID: String

  /// Creates transaction information.
  public init(transactionID: String) {
    self.transactionID = transactionID
  }
}

/// Statistics for a child job of a script.
public struct ScriptStatistics: Sendable, Hashable {
  /// What kind of script element a child job evaluated.
  public struct EvaluationKind: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The wire value.
    public var rawValue: String

    /// Creates a value from its wire representation.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The child job evaluated a statement.
    public static let statement = EvaluationKind(rawValue: "STATEMENT")
    /// The child job evaluated an expression.
    public static let expression = EvaluationKind(rawValue: "EXPRESSION")

    /// The wire value.
    public var description: String { self.rawValue }
  }

  /// A frame of the script's call stack.
  public struct StackFrame: Sendable, Hashable {
    /// The first line of the code, 1-based.
    public var startLine: Int32
    /// The first column of the code, 1-based.
    public var startColumn: Int32
    /// The last line of the code, 1-based.
    public var endLine: Int32
    /// The last column of the code, 1-based.
    public var endColumn: Int32
    /// The procedure containing the code, if any.
    public var procedureID: String?
    /// The code being run.
    public var text: String?

    /// Creates a stack frame.
    public init(
      startLine: Int32, startColumn: Int32, endLine: Int32, endColumn: Int32,
      procedureID: String? = nil, text: String? = nil
    ) {
      self.startLine = startLine
      self.startColumn = startColumn
      self.endLine = endLine
      self.endColumn = endColumn
      self.procedureID = procedureID
      self.text = text
    }
  }

  /// What the child job evaluated.
  public var evaluationKind: EvaluationKind?
  /// The call stack, innermost frame first.
  public var stackFrames: [StackFrame]

  /// Creates script statistics.
  public init(evaluationKind: EvaluationKind? = nil, stackFrames: [StackFrame] = []) {
    self.evaluationKind = evaluationKind
    self.stackFrames = stackFrames
  }
}

/// The type of a query statement, for example `SELECT` or `CREATE_TABLE`.
public struct StatementType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  /// The wire value.
  public var rawValue: String

  /// Creates a value from its wire representation.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// A `SELECT` query.
  public static let select = StatementType(rawValue: "SELECT")
  /// An `INSERT` DML statement.
  public static let insert = StatementType(rawValue: "INSERT")
  /// An `UPDATE` DML statement.
  public static let update = StatementType(rawValue: "UPDATE")
  /// A `DELETE` DML statement.
  public static let delete = StatementType(rawValue: "DELETE")
  /// A `MERGE` DML statement.
  public static let merge = StatementType(rawValue: "MERGE")
  /// A `CREATE TABLE` statement.
  public static let createTable = StatementType(rawValue: "CREATE_TABLE")
  /// A `CREATE TABLE … AS SELECT` statement.
  public static let createTableAsSelect = StatementType(rawValue: "CREATE_TABLE_AS_SELECT")
  /// A `CREATE VIEW` statement.
  public static let createView = StatementType(rawValue: "CREATE_VIEW")
  /// A `CREATE MODEL` statement.
  public static let createModel = StatementType(rawValue: "CREATE_MODEL")
  /// A `CREATE FUNCTION` statement.
  public static let createFunction = StatementType(rawValue: "CREATE_FUNCTION")
  /// A `DROP TABLE` statement.
  public static let dropTable = StatementType(rawValue: "DROP_TABLE")
  /// A `DROP VIEW` statement.
  public static let dropView = StatementType(rawValue: "DROP_VIEW")
  /// An `ALTER TABLE` statement.
  public static let alterTable = StatementType(rawValue: "ALTER_TABLE")
  /// A multi-statement script.
  public static let script = StatementType(rawValue: "SCRIPT")

  /// The wire value.
  public var description: String { self.rawValue }
}

/// Statistics specific to query jobs.
public struct QueryStatistics: Sendable, Hashable {
  /// The billing tier of the query.
  public var billingTier: Int32?
  /// Whether the results came from the query cache.
  public var cacheHit: Bool?
  /// The type of the statement.
  public var statementType: StatementType?
  /// The DDL operation performed, for example `CREATE` or `SKIP`.
  public var ddlOperationPerformed: String?
  /// The table a DDL statement targeted.
  public var ddlTargetTable: TableID?
  /// The routine a DDL statement targeted.
  public var ddlTargetRoutine: RoutineID?
  /// The dataset a DDL statement targeted.
  public var ddlTargetDataset: DatasetID?
  /// The estimated bytes processed, reported by dry runs.
  public var estimatedBytesProcessed: Int64?
  /// The number of rows affected by a DML statement.
  public var numDMLAffectedRows: Int64?
  /// Detailed DML counts.
  public var dmlStats: DMLStats?
  /// Statistics of an `EXPORT DATA` statement.
  public var exportDataStatistics: ExportDataStatistics?
  /// The tables the query referenced.
  public var referencedTables: [TableID]
  /// The routines the query referenced.
  public var referencedRoutines: [RoutineID]
  /// The bytes billed.
  public var totalBytesBilled: Int64?
  /// The bytes processed.
  public var totalBytesProcessed: Int64?
  /// The partitions processed.
  public var totalPartitionsProcessed: Int64?
  /// The slot-milliseconds consumed.
  public var totalSlotMs: Int64?
  /// The query plan.
  public var queryPlan: [QueryStage]
  /// Samples of the query's progress over time.
  public var timeline: [TimelineSample]
  /// The schema of the results, reported by dry runs.
  public var schema: Schema?
  /// Statistics of `SEARCH()` index usage.
  public var searchStatistics: SearchStatistics?
  /// Statistics of metadata cache usage, for external tables.
  public var metadataCacheStatistics: MetadataCacheStatistics?
  /// The query parameters the query uses but did not declare, reported by dry runs.
  public var undeclaredQueryParameters: [UndeclaredQueryParameter]

  /// Creates query statistics.
  public init(
    billingTier: Int32? = nil, cacheHit: Bool? = nil, statementType: StatementType? = nil,
    ddlOperationPerformed: String? = nil, ddlTargetTable: TableID? = nil,
    ddlTargetRoutine: RoutineID? = nil, ddlTargetDataset: DatasetID? = nil,
    estimatedBytesProcessed: Int64? = nil, numDMLAffectedRows: Int64? = nil,
    dmlStats: DMLStats? = nil, exportDataStatistics: ExportDataStatistics? = nil,
    referencedTables: [TableID] = [], referencedRoutines: [RoutineID] = [],
    totalBytesBilled: Int64? = nil, totalBytesProcessed: Int64? = nil,
    totalPartitionsProcessed: Int64? = nil, totalSlotMs: Int64? = nil,
    queryPlan: [QueryStage] = [], timeline: [TimelineSample] = [], schema: Schema? = nil,
    searchStatistics: SearchStatistics? = nil,
    metadataCacheStatistics: MetadataCacheStatistics? = nil,
    undeclaredQueryParameters: [UndeclaredQueryParameter] = []
  ) {
    self.billingTier = billingTier
    self.cacheHit = cacheHit
    self.statementType = statementType
    self.ddlOperationPerformed = ddlOperationPerformed
    self.ddlTargetTable = ddlTargetTable
    self.ddlTargetRoutine = ddlTargetRoutine
    self.ddlTargetDataset = ddlTargetDataset
    self.estimatedBytesProcessed = estimatedBytesProcessed
    self.numDMLAffectedRows = numDMLAffectedRows
    self.dmlStats = dmlStats
    self.exportDataStatistics = exportDataStatistics
    self.referencedTables = referencedTables
    self.referencedRoutines = referencedRoutines
    self.totalBytesBilled = totalBytesBilled
    self.totalBytesProcessed = totalBytesProcessed
    self.totalPartitionsProcessed = totalPartitionsProcessed
    self.totalSlotMs = totalSlotMs
    self.queryPlan = queryPlan
    self.timeline = timeline
    self.schema = schema
    self.searchStatistics = searchStatistics
    self.metadataCacheStatistics = metadataCacheStatistics
    self.undeclaredQueryParameters = undeclaredQueryParameters
  }
}

/// Row counts of a DML statement.
public struct DMLStats: Sendable, Hashable {
  /// The rows inserted.
  public var insertedRowCount: Int64?
  /// The rows deleted.
  public var deletedRowCount: Int64?
  /// The rows updated.
  public var updatedRowCount: Int64?

  /// Creates DML statistics.
  public init(
    insertedRowCount: Int64? = nil, deletedRowCount: Int64? = nil, updatedRowCount: Int64? = nil
  ) {
    self.insertedRowCount = insertedRowCount
    self.deletedRowCount = deletedRowCount
    self.updatedRowCount = updatedRowCount
  }
}

/// Statistics of an `EXPORT DATA` statement.
public struct ExportDataStatistics: Sendable, Hashable {
  /// The number of files written.
  public var fileCount: Int64?
  /// The number of rows exported.
  public var rowCount: Int64?

  /// Creates export statistics.
  public init(fileCount: Int64? = nil, rowCount: Int64? = nil) {
    self.fileCount = fileCount
    self.rowCount = rowCount
  }
}

/// A query parameter that a query uses without declaring it, reported by dry runs.
public struct UndeclaredQueryParameter: Sendable, Hashable {
  /// The parameter name, or `nil` for a positional parameter.
  public var name: String?
  /// The inferred type, for example `STRING` or `ARRAY`.
  public var type: String

  /// Creates an undeclared query parameter.
  public init(name: String? = nil, type: String) {
    self.name = name
    self.type = type
  }
}

/// A stage of a query plan.
public struct QueryStage: Sendable, Hashable {
  /// A step within a stage.
  public struct Step: Sendable, Hashable {
    /// The kind of step, for example `READ` or `AGGREGATE`.
    public var kind: String
    /// Human-readable descriptions of the step's work.
    public var substeps: [String]

    /// Creates a step.
    public init(kind: String, substeps: [String] = []) {
      self.kind = kind
      self.substeps = substeps
    }
  }

  /// The stage name.
  public var name: String?
  /// The stage ID, unique within the plan.
  public var id: Int64?
  /// The IDs of the stages that feed this one.
  public var inputStages: [Int64]
  /// When the stage started.
  public var startTime: Date?
  /// When the stage ended.
  public var endTime: Date?
  /// The stage status, for example `COMPLETE`.
  public var status: String?
  /// The steps of the stage.
  public var steps: [Step]
  /// Rows read by the stage.
  public var recordsRead: Int64?
  /// Rows written by the stage.
  public var recordsWritten: Int64?
  /// Parallel input segments.
  public var parallelInputs: Int64?
  /// Completed parallel input segments.
  public var completedParallelInputs: Int64?
  /// Bytes written to shuffle.
  public var shuffleOutputBytes: Int64?
  /// Bytes spilled to disk during shuffle.
  public var shuffleOutputBytesSpilled: Int64?
  /// Slot-milliseconds consumed by the stage.
  public var slotMs: Int64?
  /// Average time any worker spent waiting to be scheduled, in milliseconds.
  public var waitMsAvg: Int64?
  /// Maximum time any worker spent waiting to be scheduled, in milliseconds.
  public var waitMsMax: Int64?
  /// Average time spent waiting to be scheduled, as a ratio of the longest phase time.
  public var waitRatioAvg: Double?
  /// Maximum time spent waiting to be scheduled, as a ratio of the longest phase time.
  public var waitRatioMax: Double?
  /// Average time any worker spent reading input, in milliseconds.
  public var readMsAvg: Int64?
  /// Maximum time any worker spent reading input, in milliseconds.
  public var readMsMax: Int64?
  /// Average time spent reading input, as a ratio of the longest phase time.
  public var readRatioAvg: Double?
  /// Maximum time spent reading input, as a ratio of the longest phase time.
  public var readRatioMax: Double?
  /// Average time any worker spent computing, in milliseconds.
  public var computeMsAvg: Int64?
  /// Maximum time any worker spent computing, in milliseconds.
  public var computeMsMax: Int64?
  /// Average time spent computing, as a ratio of the longest phase time.
  public var computeRatioAvg: Double?
  /// Maximum time spent computing, as a ratio of the longest phase time.
  public var computeRatioMax: Double?
  /// Average time any worker spent writing output, in milliseconds.
  public var writeMsAvg: Int64?
  /// Maximum time any worker spent writing output, in milliseconds.
  public var writeMsMax: Int64?
  /// Average time spent writing output, as a ratio of the longest phase time.
  public var writeRatioAvg: Double?
  /// Maximum time spent writing output, as a ratio of the longest phase time.
  public var writeRatioMax: Double?

  /// Creates a query stage.
  public init(name: String? = nil, id: Int64? = nil) {
    self.name = name
    self.id = id
    self.inputStages = []
    self.steps = []
  }
}

/// A sample of a job's progress.
public struct TimelineSample: Sendable, Hashable {
  /// The time since the job started, in milliseconds.
  public var elapsedMs: Int64?
  /// The cumulative slot-milliseconds consumed.
  public var totalSlotMs: Int64?
  /// The work units pending.
  public var pendingUnits: Int64?
  /// The work units completed.
  public var completedUnits: Int64?
  /// The work units running.
  public var activeUnits: Int64?
  /// The work units that could run with more slots.
  public var estimatedRunnableUnits: Int64?

  /// Creates a timeline sample.
  public init(
    elapsedMs: Int64? = nil, totalSlotMs: Int64? = nil, pendingUnits: Int64? = nil,
    completedUnits: Int64? = nil, activeUnits: Int64? = nil, estimatedRunnableUnits: Int64? = nil
  ) {
    self.elapsedMs = elapsedMs
    self.totalSlotMs = totalSlotMs
    self.pendingUnits = pendingUnits
    self.completedUnits = completedUnits
    self.activeUnits = activeUnits
    self.estimatedRunnableUnits = estimatedRunnableUnits
  }
}

/// Statistics of `SEARCH()` index usage.
public struct SearchStatistics: Sendable, Hashable {
  /// How a search index was used.
  public struct IndexUsageMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The wire value.
    public var rawValue: String

    /// Creates a value from its wire representation.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// No index was used.
    public static let unused = IndexUsageMode(rawValue: "UNUSED")
    /// Indexes were used for part of the search.
    public static let partiallyUsed = IndexUsageMode(rawValue: "PARTIALLY_USED")
    /// Indexes were used for the whole search.
    public static let fullyUsed = IndexUsageMode(rawValue: "FULLY_USED")

    /// The wire value.
    public var description: String { self.rawValue }
  }

  /// Why an index was not used.
  public struct IndexUnusedReason: Sendable, Hashable {
    /// The reason code, for example `INDEX_CONFIG_NOT_AVAILABLE`.
    public var code: String?
    /// A human-readable explanation.
    public var message: String?
    /// The table whose index was not used.
    public var baseTable: TableID?
    /// The index that was not used.
    public var indexName: String?

    /// Creates an index-unused reason.
    public init(
      code: String? = nil, message: String? = nil, baseTable: TableID? = nil,
      indexName: String? = nil
    ) {
      self.code = code
      self.message = message
      self.baseTable = baseTable
      self.indexName = indexName
    }
  }

  /// How indexes were used.
  public var indexUsageMode: IndexUsageMode?
  /// Why indexes were not used.
  public var indexUnusedReasons: [IndexUnusedReason]

  /// Creates search statistics.
  public init(indexUsageMode: IndexUsageMode? = nil, indexUnusedReasons: [IndexUnusedReason] = []) {
    self.indexUsageMode = indexUsageMode
    self.indexUnusedReasons = indexUnusedReasons
  }
}

/// Statistics of metadata cache usage by a query over external tables.
public struct MetadataCacheStatistics: Sendable, Hashable {
  /// The cache usage for each table.
  public var tableMetadataCacheUsage: [TableMetadataCacheUsage]

  /// Creates metadata cache statistics.
  public init(tableMetadataCacheUsage: [TableMetadataCacheUsage] = []) {
    self.tableMetadataCacheUsage = tableMetadataCacheUsage
  }
}

/// The metadata cache usage for one table.
public struct TableMetadataCacheUsage: Sendable, Hashable {
  /// Why the metadata cache was not used.
  public struct UnusedReason: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The wire value.
    public var rawValue: String

    /// Creates a value from its wire representation.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The cache was older than the table's maximum staleness.
    public static let exceededMaxStaleness = UnusedReason(rawValue: "EXCEEDED_MAX_STALENESS")
    /// Metadata caching is not enabled for the table.
    public static let metadataCachingNotEnabled = UnusedReason(
      rawValue: "METADATA_CACHING_NOT_ENABLED")
    /// Another reason.
    public static let otherReason = UnusedReason(rawValue: "OTHER_REASON")

    /// The wire value.
    public var description: String { self.rawValue }
  }

  /// The table.
  public var table: TableID?
  /// Why the cache was not used, or `nil` if it was used.
  public var unusedReason: UnusedReason?
  /// A human-readable explanation.
  public var explanation: String?
  /// The table type, for example `EXTERNAL`.
  public var tableType: String?

  /// Creates table metadata cache usage.
  public init(
    table: TableID? = nil, unusedReason: UnusedReason? = nil, explanation: String? = nil,
    tableType: String? = nil
  ) {
    self.table = table
    self.unusedReason = unusedReason
    self.explanation = explanation
    self.tableType = tableType
  }
}

/// Statistics specific to load jobs.
public struct LoadStatistics: Sendable, Hashable {
  /// The number of source files.
  public var inputFiles: Int64?
  /// The bytes of source data.
  public var inputFileBytes: Int64?
  /// The rows loaded.
  public var outputRows: Int64?
  /// The bytes loaded.
  public var outputBytes: Int64?
  /// The rows rejected as bad records.
  public var badRecords: Int64?

  /// Creates load statistics.
  public init(
    inputFiles: Int64? = nil, inputFileBytes: Int64? = nil, outputRows: Int64? = nil,
    outputBytes: Int64? = nil, badRecords: Int64? = nil
  ) {
    self.inputFiles = inputFiles
    self.inputFileBytes = inputFileBytes
    self.outputRows = outputRows
    self.outputBytes = outputBytes
    self.badRecords = badRecords
  }
}

/// Statistics specific to extract jobs.
public struct ExtractStatistics: Sendable, Hashable {
  /// The number of files written to each destination URI, in order.
  public var destinationURIFileCounts: [Int64]
  /// The bytes read from the source.
  public var inputBytes: Int64?

  /// Creates extract statistics.
  public init(destinationURIFileCounts: [Int64] = [], inputBytes: Int64? = nil) {
    self.destinationURIFileCounts = destinationURIFileCounts
    self.inputBytes = inputBytes
  }
}

/// Statistics specific to copy jobs.
public struct CopyStatistics: Sendable, Hashable {
  /// The rows copied.
  public var copiedRows: Int64?
  /// The logical bytes copied.
  public var copiedLogicalBytes: Int64?

  /// Creates copy statistics.
  public init(copiedRows: Int64? = nil, copiedLogicalBytes: Int64? = nil) {
    self.copiedRows = copiedRows
    self.copiedLogicalBytes = copiedLogicalBytes
  }
}

// MARK: - Wire conversion

/// The string value of a generated wire enum, or `nil` for its `*_UNSPECIFIED` default.
func specifiedEnumValue(_ value: String?) -> String? {
  guard let value, !value.isEmpty, !value.hasSuffix("_UNSPECIFIED") else { return nil }
  return value
}

extension JobStatistics {
  init(wire: GoogleCloudBigQueryV2.JobStatistics) {
    self.init(
      creationTime: Date(millisecondsSinceEpoch: wire.creationTime),
      startTime: Date(millisecondsSinceEpoch: wire.startTime),
      endTime: Date(millisecondsSinceEpoch: wire.endTime),
      totalBytesProcessed: wire.totalBytesProcessed,
      totalSlotMs: wire.totalSlotMs,
      completionRatio: wire.completionRatio,
      numChildJobs: wire.numChildJobs == 0 ? nil : wire.numChildJobs,
      parentJobID: wire.parentJobId.nonEmpty,
      reservationID: wire.reservationId.nonEmpty,
      scriptStatistics: wire.scriptStatistics.map(ScriptStatistics.init(wire:)),
      transactionInfo: wire.transactionInfo.map {
        TransactionInfo(transactionID: $0.transactionId)
      },
      sessionInfo: wire.sessionInfo.map(SessionInfo.init(wire:)),
      query: wire.query.map(QueryStatistics.init(wire:)),
      load: wire.load.map(LoadStatistics.init(wire:)),
      extract: wire.extract.map(ExtractStatistics.init(wire:)),
      copy: wire.copy.map(CopyStatistics.init(wire:)))
  }
}

extension SessionInfo {
  init(wire: GoogleCloudBigQueryV2.SessionInfo) {
    self.init(sessionID: wire.sessionId)
  }
}

extension ScriptStatistics {
  init(wire: GoogleCloudBigQueryV2.ScriptStatistics) {
    self.init(
      evaluationKind: specifiedEnumValue(wire.evaluationKind.stringValue).map(
        EvaluationKind.init(rawValue:)),
      stackFrames: wire.stackFrames.map {
        StackFrame(
          startLine: $0.startLine, startColumn: $0.startColumn, endLine: $0.endLine,
          endColumn: $0.endColumn, procedureID: $0.procedureId.nonEmpty, text: $0.text.nonEmpty)
      })
  }
}

extension QueryStatistics {
  init(wire: GoogleCloudBigQueryV2.JobStatistics2) {
    self.init(
      billingTier: wire.billingTier,
      cacheHit: wire.cacheHit,
      statementType: wire.statementType.nonEmpty.map(StatementType.init(rawValue:)),
      ddlOperationPerformed: wire.ddlOperationPerformed.nonEmpty,
      ddlTargetTable: wire.ddlTargetTable.map(TableID.init(wire:)),
      ddlTargetRoutine: wire.ddlTargetRoutine.map(RoutineID.init(wire:)),
      ddlTargetDataset: wire.ddlTargetDataset.map(DatasetID.init(wire:)),
      estimatedBytesProcessed: wire.estimatedBytesProcessed,
      numDMLAffectedRows: wire.numDmlAffectedRows,
      dmlStats: wire.dmlStats.map(DMLStats.init(wire:)),
      exportDataStatistics: wire.exportDataStatistics.map {
        ExportDataStatistics(fileCount: $0.fileCount, rowCount: $0.rowCount)
      },
      referencedTables: wire.referencedTables.map(TableID.init(wire:)),
      referencedRoutines: wire.referencedRoutines.map(RoutineID.init(wire:)),
      totalBytesBilled: wire.totalBytesBilled,
      totalBytesProcessed: wire.totalBytesProcessed,
      totalPartitionsProcessed: wire.totalPartitionsProcessed,
      totalSlotMs: wire.totalSlotMs,
      queryPlan: wire.queryPlan.map(QueryStage.init(wire:)),
      timeline: wire.timeline.map(TimelineSample.init(wire:)),
      schema: wire.schema.map(Schema.init(wire:)),
      searchStatistics: wire.searchStatistics.map(SearchStatistics.init(wire:)),
      metadataCacheStatistics: wire.metadataCacheStatistics.map(
        MetadataCacheStatistics.init(wire:)),
      undeclaredQueryParameters: wire.undeclaredQueryParameters.map {
        UndeclaredQueryParameter(name: $0.name.nonEmpty, type: $0.parameterType?.type ?? "")
      })
  }
}

extension DMLStats {
  init(wire: GoogleCloudBigQueryV2.DmlStats) {
    self.init(
      insertedRowCount: wire.insertedRowCount, deletedRowCount: wire.deletedRowCount,
      updatedRowCount: wire.updatedRowCount)
  }
}

extension QueryStage {
  init(wire: GoogleCloudBigQueryV2.ExplainQueryStage) {
    self.init(name: wire.name.nonEmpty, id: wire.id)
    self.inputStages = wire.inputStages
    self.startTime = Date(millisecondsSinceEpoch: wire.startMs)
    self.endTime = Date(millisecondsSinceEpoch: wire.endMs)
    self.status = wire.status.nonEmpty
    self.steps = wire.steps.map { Step(kind: $0.kind, substeps: $0.substeps) }
    self.recordsRead = wire.recordsRead
    self.recordsWritten = wire.recordsWritten
    self.parallelInputs = wire.parallelInputs
    self.completedParallelInputs = wire.completedParallelInputs
    self.shuffleOutputBytes = wire.shuffleOutputBytes
    self.shuffleOutputBytesSpilled = wire.shuffleOutputBytesSpilled
    self.slotMs = wire.slotMs
    self.waitMsAvg = wire.waitMsAvg
    self.waitMsMax = wire.waitMsMax
    self.waitRatioAvg = wire.waitRatioAvg
    self.waitRatioMax = wire.waitRatioMax
    self.readMsAvg = wire.readMsAvg
    self.readMsMax = wire.readMsMax
    self.readRatioAvg = wire.readRatioAvg
    self.readRatioMax = wire.readRatioMax
    self.computeMsAvg = wire.computeMsAvg
    self.computeMsMax = wire.computeMsMax
    self.computeRatioAvg = wire.computeRatioAvg
    self.computeRatioMax = wire.computeRatioMax
    self.writeMsAvg = wire.writeMsAvg
    self.writeMsMax = wire.writeMsMax
    self.writeRatioAvg = wire.writeRatioAvg
    self.writeRatioMax = wire.writeRatioMax
  }
}

extension TimelineSample {
  init(wire: GoogleCloudBigQueryV2.QueryTimelineSample) {
    self.init(
      elapsedMs: wire.elapsedMs, totalSlotMs: wire.totalSlotMs, pendingUnits: wire.pendingUnits,
      completedUnits: wire.completedUnits, activeUnits: wire.activeUnits,
      estimatedRunnableUnits: wire.estimatedRunnableUnits)
  }
}

extension SearchStatistics {
  init(wire: GoogleCloudBigQueryV2.SearchStatistics) {
    self.init(
      indexUsageMode: specifiedEnumValue(wire.indexUsageMode.stringValue).map(
        IndexUsageMode.init(rawValue:)),
      indexUnusedReasons: wire.indexUnusedReasons.map {
        IndexUnusedReason(
          code: $0.code?.stringValue, message: $0.message,
          baseTable: $0.baseTable.map(TableID.init(wire:)), indexName: $0.indexName)
      })
  }
}

extension MetadataCacheStatistics {
  init(wire: GoogleCloudBigQueryV2.MetadataCacheStatistics) {
    self.init(
      tableMetadataCacheUsage: wire.tableMetadataCacheUsage.map {
        TableMetadataCacheUsage(
          table: $0.tableReference.map(TableID.init(wire:)),
          unusedReason: specifiedEnumValue($0.unusedReason?.stringValue).map(
            TableMetadataCacheUsage.UnusedReason.init(rawValue:)),
          explanation: $0.explanation, tableType: $0.tableType.nonEmpty)
      })
  }
}

extension LoadStatistics {
  init(wire: GoogleCloudBigQueryV2.JobStatistics3) {
    self.init(
      inputFiles: wire.inputFiles, inputFileBytes: wire.inputFileBytes,
      outputRows: wire.outputRows, outputBytes: wire.outputBytes, badRecords: wire.badRecords)
  }
}

extension ExtractStatistics {
  init(wire: GoogleCloudBigQueryV2.JobStatistics4) {
    self.init(destinationURIFileCounts: wire.destinationUriFileCounts, inputBytes: wire.inputBytes)
  }
}

extension CopyStatistics {
  init(wire: GoogleCloudBigQueryV2.CopyJobStatistics) {
    self.init(copiedRows: wire.copiedRows, copiedLogicalBytes: wire.copiedLogicalBytes)
  }
}
