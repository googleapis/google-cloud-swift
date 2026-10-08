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

import GoogleCloudBigQueryV2

/// The priority of a query job.
public struct QueryPriority: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  /// The wire value.
  public var rawValue: String

  /// Creates a value from its wire representation.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Run the query as soon as possible. The service default.
  public static let interactive = QueryPriority(rawValue: "INTERACTIVE")
  /// Queue the query until idle resources are available.
  public static let batch = QueryPriority(rawValue: "BATCH")

  /// The wire value.
  public var description: String { self.rawValue }
}

/// Which statement of a script supplies the script's result.
public struct KeyResultStatementKind: RawRepresentable, Sendable, Hashable,
  CustomStringConvertible
{
  /// The wire value.
  public var rawValue: String

  /// Creates a value from its wire representation.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The last statement that produces results.
  public static let last = KeyResultStatementKind(rawValue: "LAST")
  /// The first `SELECT` statement.
  public static let firstSelect = KeyResultStatementKind(rawValue: "FIRST_SELECT")

  /// The wire value.
  public var description: String { self.rawValue }
}

/// Options for running a multi-statement script.
public struct ScriptOptions: Sendable, Hashable {
  /// The timeout of each statement.
  public var statementTimeout: Duration?
  /// The maximum bytes billed for each statement.
  public var statementByteBudget: Int64?
  /// Which statement supplies the script's result.
  public var keyResultStatement: KeyResultStatementKind?

  /// Creates script options.
  public init(
    statementTimeout: Duration? = nil, statementByteBudget: Int64? = nil,
    keyResultStatement: KeyResultStatementKind? = nil
  ) {
    self.statementTimeout = statementTimeout
    self.statementByteBudget = statementByteBudget
    self.keyResultStatement = keyResultStatement
  }
}

/// The configuration of a query.
///
/// Queries always use GoogleSQL (standard SQL); this library does not support legacy SQL.
///
/// ```swift
/// var configuration = QueryJobConfiguration("SELECT name FROM `p.d.t` WHERE age > @age")
/// configuration.parameters = .named(["age": .int64(21)])
/// let result = try await client.query(configuration)
/// ```
public struct QueryJobConfiguration: Sendable, Equatable {
  /// The SQL text.
  public var query: String
  /// The query parameters, named or positional.
  ///
  /// Use `.positional([])` or `.named([:])` to select a parameter mode without values, for
  /// example to discover the parameters of a query with a dry run.
  public var parameters: QueryParameters?
  /// The dataset for unqualified table names in the query.
  public var defaultDataset: DatasetID?
  /// The table that receives the results. When `nil`, the service writes the results to a
  /// temporary table.
  public var destinationTable: TableID?
  /// Whether the job may create the destination table.
  public var createDisposition: CreateDisposition?
  /// What the job does when the destination table has data.
  public var writeDisposition: WriteDisposition?
  /// Schema changes the job may make to the destination table.
  public var schemaUpdateOptions: [SchemaUpdateOption]
  /// User-defined function resources for the query.
  public var userDefinedFunctions: [UserDefinedFunction]
  /// External tables the query can reference by name, as if they were tables in the default
  /// dataset. They exist only for this job.
  public var tableDefinitions: [String: ExternalDataConfiguration]
  /// The priority of the job.
  public var priority: QueryPriority?
  /// Whether results may be larger than the maximum response size. Applies only to queries
  /// with a destination table.
  public var allowLargeResults: Bool?
  /// Whether to flatten nested and repeated fields in the results.
  public var flattenResults: Bool?
  /// Whether the query may use cached results. The service default is `true`.
  public var useQueryCache: Bool?
  /// Fails the query if it would bill more bytes than this.
  public var maximumBytesBilled: Int64?
  /// Encryption of the destination table.
  public var destinationEncryption: EncryptionConfiguration?
  /// Time partitioning of the destination table.
  public var timePartitioning: TimePartitioning?
  /// Range partitioning of the destination table.
  public var rangePartitioning: RangePartitioning?
  /// Clustering of the destination table.
  public var clustering: Clustering?
  /// Options for multi-statement scripts.
  public var scriptOptions: ScriptOptions?
  /// Connection properties, for example ``ConnectionProperty/sessionID(_:)``.
  public var connectionProperties: [ConnectionProperty]
  /// Whether to start a new session. The session ID is reported in
  /// ``QueryResult/sessionInfo`` and ``JobStatistics/sessionInfo``.
  public var createSession: Bool?
  /// Validates the query and estimates its cost without running it.
  ///
  /// ``BigQueryClient/query(_:jobID:projectID:location:timeout:options:)`` rejects dry runs;
  /// use ``BigQueryClient/dryRun(_:projectID:location:options:)`` or
  /// ``BigQueryClient/createJob(_:id:selectedFields:options:)``.
  public var dryRun: Bool
  /// Labels for the job.
  public var labels: [String: String]
  /// The maximum time the job may run. The service cancels the job after it.
  public var jobTimeout: Duration?
  /// The reservation that runs the job, for example
  /// `projects/p/locations/l/reservations/r`.
  public var reservation: String?
  /// Whether ``BigQueryClient/query(_:jobID:projectID:location:timeout:options:)`` may run
  /// the query without creating a job. `nil` uses the client default.
  ///
  /// This is a property of the request, not of the job: it is not stored on the job.
  public var jobCreationMode: JobCreationMode?
  /// The maximum number of rows in each page of ``QueryResult/rows`` (the page size).
  ///
  /// Note that this bounds the size of each page fetched from the service, not the total number
  /// of rows the query produces; use a SQL `LIMIT` clause to bound the result set itself.
  public var maxResults: Int64?

  /// Creates a query configuration.
  public init(_ query: String, parameters: QueryParameters? = nil) {
    self.query = query
    self.parameters = parameters
    self.schemaUpdateOptions = []
    self.userDefinedFunctions = []
    self.tableDefinitions = [:]
    self.connectionProperties = []
    self.dryRun = false
    self.labels = [:]
  }

  var common: CommonJobFields {
    CommonJobFields(labels: self.labels, jobTimeout: self.jobTimeout, reservation: self.reservation)
  }
}

// MARK: - Fast path

extension QueryJobConfiguration {
  /// Whether `jobs.query` can run this configuration (design §6.2).
  ///
  /// This is an allowlist: a configuration that sets anything `jobs.query` does not accept
  /// runs through `jobs.insert` instead, so new fields never silently take the fast path.
  var isFastPathEligible: Bool {
    var allowed = QueryJobConfiguration(self.query, parameters: self.parameters)
    allowed.defaultDataset = self.defaultDataset
    allowed.useQueryCache = self.useQueryCache
    allowed.maximumBytesBilled = self.maximumBytesBilled
    allowed.connectionProperties = self.connectionProperties
    allowed.createSession = self.createSession
    allowed.labels = self.labels
    allowed.jobTimeout = self.jobTimeout
    allowed.reservation = self.reservation
    allowed.jobCreationMode = self.jobCreationMode
    allowed.maxResults = self.maxResults
    return allowed == self
  }

  /// The `jobs.query` request for this configuration.
  func queryRequest(
    requestID: String, location: String?, jobCreationMode: JobCreationMode?, timeout: Duration?,
    defaultProject: String
  ) -> GoogleCloudBigQueryV2.QueryRequest {
    GoogleCloudBigQueryV2.QueryRequest().with {
      $0.query = self.query
      $0.requestId = requestID
      $0.useLegacySql = false
      $0.formatOptions = RowFormat.formatOptions
      $0.location = location ?? ""
      if let jobCreationMode {
        $0.jobCreationMode = .init(stringValue: jobCreationMode.rawValue)
      }
      if let timeout {
        $0.timeoutMs = UInt32(clamping: timeout.wholeMilliseconds)
      }
      $0.maxResults = self.maxResults.map { UInt32(clamping: $0) }
      $0.defaultDataset = self.defaultDataset?.withDefaultProject(defaultProject).wire
      $0.useQueryCache = self.useQueryCache
      $0.maximumBytesBilled = self.maximumBytesBilled
      if let parameters = self.parameters {
        $0.parameterMode = parameters.wireMode
        $0.queryParameters = parameters.wire
      }
      $0.connectionProperties = self.connectionProperties.map(\.wire)
      $0.createSession = self.createSession
      $0.labels = self.labels
      $0.jobTimeoutMs = self.jobTimeout?.wholeMilliseconds
      $0.reservation = self.reservation
    }
  }
}

// MARK: - Wire conversion

extension QueryJobConfiguration {
  init(
    wire: GoogleCloudBigQueryV2.JobConfigurationQuery,
    common: GoogleCloudBigQueryV2.JobConfiguration
  ) {
    self.init(wire.query)
    if !wire.queryParameters.isEmpty || !wire.parameterMode.isEmpty {
      // Without a mode, unnamed parameters can only be positional. A parameter the library
      // can't read leaves `parameters` nil rather than failing the whole job.
      let unnamed = wire.queryParameters.allSatisfy { $0.name.isEmpty }
      self.parameters = try? QueryParameters(
        wire: wire.queryParameters,
        mode: wire.parameterMode.nonEmpty ?? (unnamed ? "POSITIONAL" : "NAMED"))
    }
    self.defaultDataset = wire.defaultDataset.map(DatasetID.init(wire:))
    self.destinationTable = wire.destinationTable.map(TableID.init(wire:))
    self.createDisposition = wire.createDisposition.nonEmpty.map(CreateDisposition.init)
    self.writeDisposition = wire.writeDisposition.nonEmpty.map(WriteDisposition.init)
    self.schemaUpdateOptions = wire.schemaUpdateOptions.map(SchemaUpdateOption.init(rawValue:))
    self.userDefinedFunctions = wire.userDefinedFunctionResources.compactMap(
      UserDefinedFunction.init(wire:))
    self.tableDefinitions = wire.externalTableDefinitions.mapValues(
      ExternalDataConfiguration.init(wire:))
    self.priority = wire.priority.nonEmpty.map(QueryPriority.init(rawValue:))
    self.allowLargeResults = wire.allowLargeResults
    self.flattenResults = wire.flattenResults
    self.useQueryCache = wire.useQueryCache
    self.maximumBytesBilled = wire.maximumBytesBilled
    self.destinationEncryption = wire.destinationEncryptionConfiguration.map(
      EncryptionConfiguration.init(wire:))
    self.timePartitioning = wire.timePartitioning.map(TimePartitioning.init(wire:))
    self.rangePartitioning = wire.rangePartitioning.map(RangePartitioning.init(wire:))
    self.clustering = wire.clustering.map(Clustering.init(wire:))
    self.scriptOptions = wire.scriptOptions.map(ScriptOptions.init(wire:))
    self.connectionProperties = wire.connectionProperties.map(ConnectionProperty.init(wire:))
    self.createSession = wire.createSession
    self.dryRun = common.dryRun ?? false
    let shared = CommonJobFields(wire: common)
    self.labels = shared.labels
    self.jobTimeout = shared.jobTimeout
    self.reservation = shared.reservation
  }

  var wire: GoogleCloudBigQueryV2.JobConfigurationQuery {
    GoogleCloudBigQueryV2.JobConfigurationQuery().with {
      $0.query = self.query
      $0.useLegacySql = false
      if let parameters = self.parameters {
        $0.parameterMode = parameters.wireMode
        $0.queryParameters = parameters.wire
      }
      $0.defaultDataset = self.defaultDataset?.wire
      $0.destinationTable = self.destinationTable?.wire
      $0.createDisposition = self.createDisposition?.rawValue ?? ""
      $0.writeDisposition = self.writeDisposition?.rawValue ?? ""
      $0.schemaUpdateOptions = self.schemaUpdateOptions.map(\.rawValue)
      $0.userDefinedFunctionResources = self.userDefinedFunctions.map(\.wire)
      $0.externalTableDefinitions = self.tableDefinitions.mapValues(\.wire)
      $0.priority = self.priority?.rawValue ?? ""
      $0.allowLargeResults = self.allowLargeResults
      $0.flattenResults = self.flattenResults
      $0.useQueryCache = self.useQueryCache
      $0.maximumBytesBilled = self.maximumBytesBilled
      $0.destinationEncryptionConfiguration = self.destinationEncryption?.wire
      $0.timePartitioning = self.timePartitioning?.wire
      $0.rangePartitioning = self.rangePartitioning?.wire
      $0.clustering = self.clustering?.wire
      $0.scriptOptions = self.scriptOptions?.wire
      $0.connectionProperties = self.connectionProperties.map(\.wire)
      $0.createSession = self.createSession
    }
  }

  /// Converts wire parameters. The wire type and value are kept as they are, so every
  /// parameter type round-trips.
  func withDefaultProject(_ projectID: String) -> QueryJobConfiguration {
    var copy = self
    copy.defaultDataset = copy.defaultDataset?.withDefaultProject(projectID)
    copy.destinationTable = copy.destinationTable?.withDefaultProject(projectID)
    return copy
  }
}

extension ScriptOptions {
  init(wire: GoogleCloudBigQueryV2.ScriptOptions) {
    self.init(
      statementTimeout: wire.statementTimeoutMs.map { .milliseconds($0) },
      statementByteBudget: wire.statementByteBudget,
      keyResultStatement: specifiedEnumValue(wire.keyResultStatement.stringValue).map(
        KeyResultStatementKind.init(rawValue:)))
  }

  var wire: GoogleCloudBigQueryV2.ScriptOptions {
    GoogleCloudBigQueryV2.ScriptOptions().with {
      $0.statementTimeoutMs = self.statementTimeout?.wholeMilliseconds
      $0.statementByteBudget = self.statementByteBudget
      if let kind = self.keyResultStatement {
        $0.keyResultStatement = .init(stringValue: kind.rawValue)
      }
    }
  }
}
