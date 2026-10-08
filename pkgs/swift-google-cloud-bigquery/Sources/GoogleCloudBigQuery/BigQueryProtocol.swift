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
public import GoogleGax

/// A protocol covering the operations of ``BigQueryClient``, suitable for test doubles.
///
/// Every requirement has a default implementation that throws
/// `GoogleGax.RequestError.unimplemented`, so a mock or fake type only needs to implement the
/// methods exercised by a test.
public protocol BigQueryProtocol: Sendable {
  /// The project used for requests that do not name a project explicitly.
  var projectID: String { get }

  /// The default location for jobs and queries.
  var location: String? { get }

  // MARK: - Datasets

  /// Creates a dataset (`datasets.insert`).
  @discardableResult
  func createDataset(
    _ dataset: Dataset,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Dataset

  /// Fetches a dataset (`datasets.get`), or returns `nil` if it does not exist.
  func getDataset(
    _ id: DatasetID,
    view: DatasetView?,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Dataset?

  /// Lists the datasets in a project (`datasets.list`).
  func listDatasets(
    projectID: String?,
    all: Bool,
    filter: String?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Dataset>

  /// Patches a dataset (`datasets.patch`).
  func updateDataset(
    _ dataset: Dataset,
    clearing: Set<Dataset.Field>,
    updateMode: DatasetUpdateMode?,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Dataset

  /// Deletes a dataset (`datasets.delete`), returning `false` if it did not exist.
  @discardableResult
  func deleteDataset(
    _ id: DatasetID,
    deleteContents: Bool,
    options: RequestOptions
  ) async throws -> Bool

  // MARK: - Tables

  /// Creates a table, view, materialized view, snapshot, or clone (`tables.insert`).
  @discardableResult
  func createTable(
    _ table: Table,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table

  /// Fetches a table (`tables.get`), or returns `nil` if it does not exist.
  func getTable(
    _ id: TableID,
    view: TableMetadataView?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table?

  /// Lists the tables in a dataset (`tables.list`).
  func listTables(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Table>

  /// Patches a table (`tables.patch`).
  func updateTable(
    _ table: Table,
    clearing: Set<Table.Field>,
    autodetectSchema: Bool,
    ifMatch etag: String?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table

  /// Deletes a table (`tables.delete`), returning `false` if it did not exist.
  @discardableResult
  func deleteTable(
    _ id: TableID,
    options: RequestOptions
  ) async throws -> Bool

  /// Returns the partition IDs of a partitioned table.
  func listPartitions(
    of table: TableID,
    options: RequestOptions
  ) async throws -> [String]

  /// Reads the rows of a table (`tabledata.list`).
  func listRows(
    in table: TableID,
    schema: Schema?,
    selectedFields: [String]?,
    startIndex: UInt64?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) async throws -> RowSequence

  /// Streams rows into a table (`tabledata.insertAll`).
  func insertAll(
    _ rows: [InsertRow],
    into table: TableID,
    skipInvalidRows: Bool,
    ignoreUnknownValues: Bool,
    templateSuffix: String?,
    insertIDs: InsertIDPolicy,
    options: RequestOptions
  ) async throws -> InsertAllResponse

  // MARK: - Routines

  /// Creates a routine (`routines.insert`).
  @discardableResult
  func createRoutine(
    _ routine: Routine,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Routine

  /// Fetches a routine (`routines.get`), or returns `nil` if it does not exist.
  func getRoutine(
    _ id: RoutineID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Routine?

  /// Lists the routines in a dataset (`routines.list`).
  func listRoutines(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Routine>

  /// Replaces a routine (`routines.update`).
  func updateRoutine(
    _ routine: Routine,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Routine

  /// Deletes a routine (`routines.delete`), returning `false` if it did not exist.
  @discardableResult
  func deleteRoutine(
    _ id: RoutineID,
    options: RequestOptions
  ) async throws -> Bool

  // MARK: - Models

  /// Fetches a model (`models.get`), or returns `nil` if it does not exist.
  func getModel(
    _ id: ModelID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Model?

  /// Lists the models in a dataset (`models.list`).
  func listModels(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Model>

  /// Patches a model (`models.patch`).
  func updateModel(
    _ model: Model,
    clearing: Set<Model.Field>,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Model

  /// Deletes a model (`models.delete`), returning `false` if it did not exist.
  @discardableResult
  func deleteModel(
    _ id: ModelID,
    options: RequestOptions
  ) async throws -> Bool

  // MARK: - IAM and Projects

  /// Fetches the IAM policy of a table (`tables.getIamPolicy`).
  func getIAMPolicy(
    for table: TableID,
    requestedPolicyVersion: Int32?,
    options: RequestOptions
  ) async throws -> IAMPolicy

  /// Replaces the IAM policy of a table (`tables.setIamPolicy`).
  func setIAMPolicy(
    _ policy: IAMPolicy,
    for table: TableID,
    options: RequestOptions
  ) async throws -> IAMPolicy

  /// Returns the subset of `permissions` the caller holds on `table` (`tables.testIamPermissions`).
  func testIAMPermissions(
    _ permissions: [String],
    for table: TableID,
    options: RequestOptions
  ) async throws -> [String]

  /// Returns the email address of the project's BigQuery encryption service account.
  func getServiceAccount(
    projectID: String?,
    options: RequestOptions
  ) async throws -> String

  /// Lists the projects the caller is a member of (`projects.list`).
  func listProjects(
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Project>

  // MARK: - Jobs, Queries, and Uploads

  /// Starts an asynchronous job (`jobs.insert`).
  func createJob(
    _ configuration: JobConfiguration,
    id: JobID?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Job

  /// Starts a job and waits for it to finish.
  @discardableResult
  func runJob(
    _ configuration: JobConfiguration,
    id: JobID?,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> Job

  /// Fetches a job (`jobs.get`), or returns `nil` if it does not exist.
  func getJob(
    _ id: JobID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Job?

  /// Lists jobs in a project (`jobs.list`).
  func listJobs(
    projectID: String?,
    allUsers: Bool,
    stateFilter: Set<JobState>,
    parentJob: JobID?,
    minCreationTime: Date?,
    maxCreationTime: Date?,
    selectedFields: [String]?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Job>

  /// Requests cancellation of a job (`jobs.cancel`), returning `false` if it did not exist.
  @discardableResult
  func cancelJob(
    _ id: JobID,
    options: RequestOptions
  ) async throws -> Bool

  /// Deletes the metadata of a finished job (`jobs.delete`), returning `false` if it did not exist.
  @discardableResult
  func deleteJob(
    _ id: JobID,
    options: RequestOptions
  ) async throws -> Bool

  /// Polls `jobs.get` until the job reaches ``JobState/done``.
  @discardableResult
  func waitForJob(
    _ id: JobID,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> Job

  /// Runs a GoogleSQL query and waits for its first page of results.
  func query(
    _ configuration: QueryJobConfiguration,
    jobID: JobID?,
    projectID: String?,
    location: String?,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> QueryResult

  /// Runs a GoogleSQL query string with optional parameters and page size.
  func query(
    _ sql: String,
    parameters: QueryParameters?,
    pageSize: Int?,
    options: RequestOptions
  ) async throws -> QueryResult

  /// Waits for a query job to finish and fetches its results (`jobs.getQueryResults`).
  func getQueryResults(
    _ job: JobID,
    startIndex: UInt64?,
    pageSize: Int?,
    options: RequestOptions
  ) async throws -> QueryResult

  /// Validates a query and estimates its cost without running it (`dryRun`).
  func dryRun(
    _ configuration: QueryJobConfiguration,
    projectID: String?,
    location: String?,
    options: RequestOptions
  ) async throws -> QueryDryRunResult

  /// Validates a GoogleSQL query string and estimates its cost without running it.
  func dryRun(
    _ sql: String,
    parameters: QueryParameters?,
    options: RequestOptions
  ) async throws -> QueryDryRunResult

  /// Uploads local bytes into a table using a resumable upload session.
  func load(
    _ source: UploadSource,
    configuration: LoadJobConfiguration,
    jobID: JobID?,
    chunkSize: Int,
    options: RequestOptions
  ) async throws -> Job
}

// MARK: - Default Unimplemented Witnesses

extension BigQueryProtocol {
  /// Defaults to `""` for test doubles that do not need a project ID.
  public var projectID: String { "" }

  /// Defaults to `nil`.
  public var location: String? { nil }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func createDataset(
    _ dataset: Dataset,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Dataset {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getDataset(
    _ id: DatasetID,
    view: DatasetView?,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Dataset? {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listDatasets(
    projectID: String?,
    all: Bool,
    filter: String?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Dataset> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func updateDataset(
    _ dataset: Dataset,
    clearing: Set<Dataset.Field>,
    updateMode: DatasetUpdateMode?,
    accessPolicyVersion: Int32?,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Dataset {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func deleteDataset(
    _ id: DatasetID,
    deleteContents: Bool,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func createTable(
    _ table: Table,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getTable(
    _ id: TableID,
    view: TableMetadataView?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table? {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listTables(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Table> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func updateTable(
    _ table: Table,
    clearing: Set<Table.Field>,
    autodetectSchema: Bool,
    ifMatch etag: String?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Table {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func deleteTable(
    _ id: TableID,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func listPartitions(
    of table: TableID,
    options: RequestOptions
  ) async throws -> [String] {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func listRows(
    in table: TableID,
    schema: Schema?,
    selectedFields: [String]?,
    startIndex: UInt64?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) async throws -> RowSequence {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func insertAll(
    _ rows: [InsertRow],
    into table: TableID,
    skipInvalidRows: Bool,
    ignoreUnknownValues: Bool,
    templateSuffix: String?,
    insertIDs: InsertIDPolicy,
    options: RequestOptions
  ) async throws -> InsertAllResponse {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func createRoutine(
    _ routine: Routine,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Routine {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getRoutine(
    _ id: RoutineID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Routine? {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listRoutines(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Routine> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func updateRoutine(
    _ routine: Routine,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Routine {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func deleteRoutine(
    _ id: RoutineID,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getModel(
    _ id: ModelID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Model? {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listModels(
    in dataset: DatasetID,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Model> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func updateModel(
    _ model: Model,
    clearing: Set<Model.Field>,
    selectedFields: [String]?,
    ifMatch etag: String?,
    options: RequestOptions
  ) async throws -> Model {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func deleteModel(
    _ id: ModelID,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getIAMPolicy(
    for table: TableID,
    requestedPolicyVersion: Int32?,
    options: RequestOptions
  ) async throws -> IAMPolicy {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func setIAMPolicy(
    _ policy: IAMPolicy,
    for table: TableID,
    options: RequestOptions
  ) async throws -> IAMPolicy {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func testIAMPermissions(
    _ permissions: [String],
    for table: TableID,
    options: RequestOptions
  ) async throws -> [String] {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getServiceAccount(
    projectID: String?,
    options: RequestOptions
  ) async throws -> String {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listProjects(
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Project> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func createJob(
    _ configuration: JobConfiguration,
    id: JobID?,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Job {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Creates the job via ``createJob(_:id:selectedFields:options:)`` and waits via
  /// ``waitForJob(_:timeout:options:)`` unless overridden.
  @discardableResult
  public func runJob(
    _ configuration: JobConfiguration,
    id: JobID?,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> Job {
    let job = try await self.createJob(
      configuration, id: id, selectedFields: nil, options: options)
    return try await self.waitForJob(job.id, timeout: timeout, options: options)
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getJob(
    _ id: JobID,
    selectedFields: [String]?,
    options: RequestOptions
  ) async throws -> Job? {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Returns a sequence whose first page throws `GoogleGax.RequestError.unimplemented`.
  public func listJobs(
    projectID: String?,
    allUsers: Bool,
    stateFilter: Set<JobState>,
    parentJob: JobID?,
    minCreationTime: Date?,
    maxCreationTime: Date?,
    selectedFields: [String]?,
    pageSize: Int?,
    pageToken: String?,
    options: RequestOptions
  ) -> PagedSequence<Job> {
    PagedSequence { _ in throw GoogleGax.RequestError.unimplemented }
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func cancelJob(
    _ id: JobID,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func deleteJob(
    _ id: JobID,
    options: RequestOptions
  ) async throws -> Bool {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  @discardableResult
  public func waitForJob(
    _ id: JobID,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> Job {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func query(
    _ configuration: QueryJobConfiguration,
    jobID: JobID?,
    projectID: String?,
    location: String?,
    timeout: Duration?,
    options: RequestOptions
  ) async throws -> QueryResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Forwards to ``query(_:jobID:projectID:location:timeout:options:)`` unless overridden.
  public func query(
    _ sql: String,
    parameters: QueryParameters?,
    pageSize: Int?,
    options: RequestOptions
  ) async throws -> QueryResult {
    var config = QueryJobConfiguration(sql, parameters: parameters)
    config.maxResults = pageSize.map(Int64.init)
    return try await self.query(
      config, jobID: nil, projectID: nil, location: nil, timeout: nil, options: options)
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func getQueryResults(
    _ job: JobID,
    startIndex: UInt64?,
    pageSize: Int?,
    options: RequestOptions
  ) async throws -> QueryResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func dryRun(
    _ configuration: QueryJobConfiguration,
    projectID: String?,
    location: String?,
    options: RequestOptions
  ) async throws -> QueryDryRunResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Forwards to ``dryRun(_:projectID:location:options:)`` unless overridden.
  public func dryRun(
    _ sql: String,
    parameters: QueryParameters?,
    options: RequestOptions
  ) async throws -> QueryDryRunResult {
    let config = QueryJobConfiguration(sql, parameters: parameters)
    return try await self.dryRun(config, projectID: nil, location: nil, options: options)
  }

  /// Throws `GoogleGax.RequestError.unimplemented` unless overridden.
  public func load(
    _ source: UploadSource,
    configuration: LoadJobConfiguration,
    jobID: JobID?,
    chunkSize: Int,
    options: RequestOptions
  ) async throws -> Job {
    throw GoogleGax.RequestError.unimplemented
  }
}

// MARK: - Forwarding Overloads With Default Arguments

extension BigQueryProtocol {
  /// Creates a dataset with default options.
  @_disfavoredOverload
  @discardableResult
  public func createDataset(
    _ dataset: Dataset,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil
  ) async throws -> Dataset {
    try await self.createDataset(
      dataset, accessPolicyVersion: accessPolicyVersion, selectedFields: selectedFields,
      options: .init())
  }

  /// Fetches a dataset with default options.
  @_disfavoredOverload
  public func getDataset(
    _ id: DatasetID,
    view: DatasetView? = nil,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil
  ) async throws -> Dataset? {
    try await self.getDataset(
      id, view: view, accessPolicyVersion: accessPolicyVersion, selectedFields: selectedFields,
      options: .init())
  }

  /// Lists datasets with default options.
  @_disfavoredOverload
  public func listDatasets(
    projectID: String? = nil,
    all: Bool = false,
    filter: String? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Dataset> {
    self.listDatasets(
      projectID: projectID, all: all, filter: filter, pageSize: pageSize, pageToken: pageToken,
      options: .init())
  }

  /// Patches a dataset with default options.
  @_disfavoredOverload
  public func updateDataset(
    _ dataset: Dataset,
    clearing: Set<Dataset.Field> = [],
    updateMode: DatasetUpdateMode? = nil,
    accessPolicyVersion: Int32? = nil,
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil
  ) async throws -> Dataset {
    try await self.updateDataset(
      dataset, clearing: clearing, updateMode: updateMode,
      accessPolicyVersion: accessPolicyVersion, selectedFields: selectedFields, ifMatch: etag,
      options: .init())
  }

  /// Deletes a dataset with default options.
  @_disfavoredOverload
  @discardableResult
  public func deleteDataset(
    _ id: DatasetID,
    deleteContents: Bool = false
  ) async throws -> Bool {
    try await self.deleteDataset(id, deleteContents: deleteContents, options: .init())
  }

  /// Creates a table with default options.
  @_disfavoredOverload
  @discardableResult
  public func createTable(
    _ table: Table,
    selectedFields: [String]? = nil
  ) async throws -> Table {
    try await self.createTable(table, selectedFields: selectedFields, options: .init())
  }

  /// Fetches a table with default options.
  @_disfavoredOverload
  public func getTable(
    _ id: TableID,
    view: TableMetadataView? = nil,
    selectedFields: [String]? = nil
  ) async throws -> Table? {
    try await self.getTable(id, view: view, selectedFields: selectedFields, options: .init())
  }

  /// Lists tables in a dataset with default options.
  @_disfavoredOverload
  public func listTables(
    in dataset: DatasetID,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Table> {
    self.listTables(in: dataset, pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Patches a table with default options.
  @_disfavoredOverload
  public func updateTable(
    _ table: Table,
    clearing: Set<Table.Field> = [],
    autodetectSchema: Bool = false,
    ifMatch etag: String? = nil,
    selectedFields: [String]? = nil
  ) async throws -> Table {
    try await self.updateTable(
      table, clearing: clearing, autodetectSchema: autodetectSchema, ifMatch: etag,
      selectedFields: selectedFields, options: .init())
  }

  /// Deletes a table with default options.
  @_disfavoredOverload
  @discardableResult
  public func deleteTable(_ id: TableID) async throws -> Bool {
    try await self.deleteTable(id, options: .init())
  }

  /// Returns the partition IDs of a partitioned table with default options.
  @_disfavoredOverload
  public func listPartitions(of table: TableID) async throws -> [String] {
    try await self.listPartitions(of: table, options: .init())
  }

  /// Reads the rows of a table with default options.
  @_disfavoredOverload
  public func listRows(
    in table: TableID,
    schema: Schema? = nil,
    selectedFields: [String]? = nil,
    startIndex: UInt64? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) async throws -> RowSequence {
    try await self.listRows(
      in: table, schema: schema, selectedFields: selectedFields, startIndex: startIndex,
      pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Streams rows into a table with default options.
  @_disfavoredOverload
  public func insertAll(
    _ rows: [InsertRow],
    into table: TableID,
    skipInvalidRows: Bool = false,
    ignoreUnknownValues: Bool = false,
    templateSuffix: String? = nil,
    insertIDs: InsertIDPolicy = .generateMissing
  ) async throws -> InsertAllResponse {
    try await self.insertAll(
      rows, into: table, skipInvalidRows: skipInvalidRows,
      ignoreUnknownValues: ignoreUnknownValues, templateSuffix: templateSuffix,
      insertIDs: insertIDs, options: .init())
  }

  /// Streams `Encodable` values into a table, encoding each via ``InsertRow/init(_:insertID:)``.
  @_disfavoredOverload
  public func insertAll<T: Encodable>(
    _ values: some Sequence<T>,
    into table: TableID,
    skipInvalidRows: Bool = false,
    ignoreUnknownValues: Bool = false,
    templateSuffix: String? = nil,
    insertIDs: InsertIDPolicy = .generateMissing,
    options: RequestOptions = .init()
  ) async throws -> InsertAllResponse {
    try await self.insertAll(
      values.map { try InsertRow($0) }, into: table, skipInvalidRows: skipInvalidRows,
      ignoreUnknownValues: ignoreUnknownValues, templateSuffix: templateSuffix,
      insertIDs: insertIDs, options: options)
  }

  /// Creates a routine with default options.
  @_disfavoredOverload
  @discardableResult
  public func createRoutine(
    _ routine: Routine,
    selectedFields: [String]? = nil
  ) async throws -> Routine {
    try await self.createRoutine(routine, selectedFields: selectedFields, options: .init())
  }

  /// Fetches a routine with default options.
  @_disfavoredOverload
  public func getRoutine(
    _ id: RoutineID,
    selectedFields: [String]? = nil
  ) async throws -> Routine? {
    try await self.getRoutine(id, selectedFields: selectedFields, options: .init())
  }

  /// Lists routines in a dataset with default options.
  @_disfavoredOverload
  public func listRoutines(
    in dataset: DatasetID,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Routine> {
    self.listRoutines(in: dataset, pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Replaces a routine with default options.
  @_disfavoredOverload
  public func updateRoutine(
    _ routine: Routine,
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil
  ) async throws -> Routine {
    try await self.updateRoutine(
      routine, selectedFields: selectedFields, ifMatch: etag, options: .init())
  }

  /// Deletes a routine with default options.
  @_disfavoredOverload
  @discardableResult
  public func deleteRoutine(_ id: RoutineID) async throws -> Bool {
    try await self.deleteRoutine(id, options: .init())
  }

  /// Fetches a model with default options.
  @_disfavoredOverload
  public func getModel(
    _ id: ModelID,
    selectedFields: [String]? = nil
  ) async throws -> Model? {
    try await self.getModel(id, selectedFields: selectedFields, options: .init())
  }

  /// Lists models in a dataset with default options.
  @_disfavoredOverload
  public func listModels(
    in dataset: DatasetID,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Model> {
    self.listModels(in: dataset, pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Patches a model with default options.
  @_disfavoredOverload
  public func updateModel(
    _ model: Model,
    clearing: Set<Model.Field> = [],
    selectedFields: [String]? = nil,
    ifMatch etag: String? = nil
  ) async throws -> Model {
    try await self.updateModel(
      model, clearing: clearing, selectedFields: selectedFields, ifMatch: etag, options: .init())
  }

  /// Deletes a model with default options.
  @_disfavoredOverload
  @discardableResult
  public func deleteModel(_ id: ModelID) async throws -> Bool {
    try await self.deleteModel(id, options: .init())
  }

  /// Fetches the IAM policy of a table with default options.
  @_disfavoredOverload
  public func getIAMPolicy(
    for table: TableID,
    requestedPolicyVersion: Int32? = nil
  ) async throws -> IAMPolicy {
    try await self.getIAMPolicy(
      for: table, requestedPolicyVersion: requestedPolicyVersion, options: .init())
  }

  /// Replaces the IAM policy of a table with default options.
  @_disfavoredOverload
  public func setIAMPolicy(
    _ policy: IAMPolicy,
    for table: TableID
  ) async throws -> IAMPolicy {
    try await self.setIAMPolicy(policy, for: table, options: .init())
  }

  /// Tests IAM permissions on a table with default options.
  @_disfavoredOverload
  public func testIAMPermissions(
    _ permissions: [String],
    for table: TableID
  ) async throws -> [String] {
    try await self.testIAMPermissions(permissions, for: table, options: .init())
  }

  /// Returns the project's BigQuery encryption service account with default options.
  @_disfavoredOverload
  public func getServiceAccount(
    projectID: String? = nil
  ) async throws -> String {
    try await self.getServiceAccount(projectID: projectID, options: .init())
  }

  /// Lists projects with default options.
  @_disfavoredOverload
  public func listProjects(
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Project> {
    self.listProjects(pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Starts an asynchronous job with default options.
  @_disfavoredOverload
  public func createJob(
    _ configuration: JobConfiguration,
    id: JobID? = nil,
    selectedFields: [String]? = nil
  ) async throws -> Job {
    try await self.createJob(
      configuration, id: id, selectedFields: selectedFields, options: .init())
  }

  /// Starts a job and waits for it to finish with default options.
  @_disfavoredOverload
  @discardableResult
  public func runJob(
    _ configuration: JobConfiguration,
    id: JobID? = nil,
    timeout: Duration? = nil
  ) async throws -> Job {
    try await self.runJob(configuration, id: id, timeout: timeout, options: .init())
  }

  /// Fetches a job with default options.
  @_disfavoredOverload
  public func getJob(
    _ id: JobID,
    selectedFields: [String]? = nil
  ) async throws -> Job? {
    try await self.getJob(id, selectedFields: selectedFields, options: .init())
  }

  /// Lists jobs with default options.
  @_disfavoredOverload
  public func listJobs(
    projectID: String? = nil,
    allUsers: Bool = false,
    stateFilter: Set<JobState> = [],
    parentJob: JobID? = nil,
    minCreationTime: Date? = nil,
    maxCreationTime: Date? = nil,
    selectedFields: [String]? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) -> PagedSequence<Job> {
    self.listJobs(
      projectID: projectID, allUsers: allUsers, stateFilter: stateFilter, parentJob: parentJob,
      minCreationTime: minCreationTime, maxCreationTime: maxCreationTime,
      selectedFields: selectedFields, pageSize: pageSize, pageToken: pageToken, options: .init())
  }

  /// Requests cancellation of a job with default options.
  @_disfavoredOverload
  @discardableResult
  public func cancelJob(_ id: JobID) async throws -> Bool {
    try await self.cancelJob(id, options: .init())
  }

  /// Deletes the metadata of a finished job with default options.
  @_disfavoredOverload
  @discardableResult
  public func deleteJob(_ id: JobID) async throws -> Bool {
    try await self.deleteJob(id, options: .init())
  }

  /// Polls `jobs.get` until the job finishes with default options.
  @_disfavoredOverload
  @discardableResult
  public func waitForJob(
    _ id: JobID,
    timeout: Duration? = nil
  ) async throws -> Job {
    try await self.waitForJob(id, timeout: timeout, options: .init())
  }

  /// Runs a GoogleSQL query configuration with default options.
  @_disfavoredOverload
  public func query(
    _ configuration: QueryJobConfiguration,
    jobID: JobID? = nil,
    projectID: String? = nil,
    location: String? = nil,
    timeout: Duration? = nil
  ) async throws -> QueryResult {
    try await self.query(
      configuration, jobID: jobID, projectID: projectID, location: location, timeout: timeout,
      options: .init())
  }

  /// Runs a GoogleSQL query string with default options.
  @_disfavoredOverload
  public func query(
    _ sql: String,
    parameters: QueryParameters? = nil,
    pageSize: Int? = nil
  ) async throws -> QueryResult {
    try await self.query(sql, parameters: parameters, pageSize: pageSize, options: .init())
  }

  /// Waits for a query job and fetches its results with default options.
  @_disfavoredOverload
  public func getQueryResults(
    _ job: JobID,
    startIndex: UInt64? = nil,
    pageSize: Int? = nil
  ) async throws -> QueryResult {
    try await self.getQueryResults(
      job, startIndex: startIndex, pageSize: pageSize, options: .init())
  }

  /// Validates a query configuration without running it with default options.
  @_disfavoredOverload
  public func dryRun(
    _ configuration: QueryJobConfiguration,
    projectID: String? = nil,
    location: String? = nil
  ) async throws -> QueryDryRunResult {
    try await self.dryRun(configuration, projectID: projectID, location: location, options: .init())
  }

  /// Validates a GoogleSQL query string without running it with default options.
  @_disfavoredOverload
  public func dryRun(
    _ sql: String,
    parameters: QueryParameters? = nil
  ) async throws -> QueryDryRunResult {
    try await self.dryRun(sql, parameters: parameters, options: .init())
  }

  /// Uploads local bytes into a table with default options.
  @_disfavoredOverload
  public func load(
    _ source: UploadSource,
    configuration: LoadJobConfiguration,
    jobID: JobID? = nil,
    chunkSize: Int = 15 << 20
  ) async throws -> Job {
    try await self.load(
      source, configuration: configuration, jobID: jobID, chunkSize: chunkSize, options: .init())
  }
}
