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

/// Identifies a dataset.
///
/// A `nil` ``projectID`` means the project of the ``BigQueryClient``.
public struct DatasetID: Sendable, Hashable, CustomStringConvertible {
  /// The project containing the dataset, or `nil` for the client project.
  public var projectID: String?

  /// The dataset ID within the project.
  public var datasetID: String

  /// Creates a dataset ID.
  public init(projectID: String? = nil, datasetID: String) {
    self.projectID = projectID
    self.datasetID = datasetID
  }

  /// Parses `dataset` or `project.dataset`.
  ///
  /// The legacy `project:dataset` form is also accepted.
  public init(_ string: String) throws {
    let (project, parts) = try parseResourcePath(string, count: 1, kind: "dataset")
    self.init(projectID: project, datasetID: parts[0])
  }

  /// The Standard SQL form, `project.dataset`, or `dataset` if there is no project.
  public var description: String { joinResourcePath(self.projectID, [self.datasetID]) }
}

/// Identifies a table, view, materialized view, or snapshot.
///
/// A `nil` ``projectID`` means the project of the ``BigQueryClient``.
public struct TableID: Sendable, Hashable, CustomStringConvertible {
  /// The project containing the table, or `nil` for the client project.
  public var projectID: String?

  /// The dataset containing the table.
  public var datasetID: String

  /// The table ID within the dataset. May include a partition decorator, such as `t$20240101`.
  public var tableID: String

  /// Creates a table ID.
  public init(projectID: String? = nil, datasetID: String, tableID: String) {
    self.projectID = projectID
    self.datasetID = datasetID
    self.tableID = tableID
  }

  /// Creates the ID of the table `tableID` in `dataset`.
  public init(dataset: DatasetID, tableID: String) {
    self.init(projectID: dataset.projectID, datasetID: dataset.datasetID, tableID: tableID)
  }

  /// Parses `dataset.table` or `project.dataset.table`.
  ///
  /// The legacy `project:dataset.table` form is also accepted.
  public init(_ string: String) throws {
    let (project, parts) = try parseResourcePath(string, count: 2, kind: "table")
    self.init(projectID: project, datasetID: parts[0], tableID: parts[1])
  }

  /// The dataset containing this table.
  public var dataset: DatasetID { DatasetID(projectID: self.projectID, datasetID: self.datasetID) }

  /// The Standard SQL form, `project.dataset.table`.
  public var description: String {
    joinResourcePath(self.projectID, [self.datasetID, self.tableID])
  }

  /// The IAM resource name, `projects/p/datasets/d/tables/t`.
  ///
  /// The project must already be resolved.
  var iamResourceName: String {
    "projects/\(self.projectID ?? "")/datasets/\(self.datasetID)/tables/\(self.tableID)"
  }
}

/// Identifies a routine: a user-defined function, table function, or stored procedure.
///
/// A `nil` ``projectID`` means the project of the ``BigQueryClient``.
public struct RoutineID: Sendable, Hashable, CustomStringConvertible {
  /// The project containing the routine, or `nil` for the client project.
  public var projectID: String?

  /// The dataset containing the routine.
  public var datasetID: String

  /// The routine ID within the dataset.
  public var routineID: String

  /// Creates a routine ID.
  public init(projectID: String? = nil, datasetID: String, routineID: String) {
    self.projectID = projectID
    self.datasetID = datasetID
    self.routineID = routineID
  }

  /// Creates the ID of the routine `routineID` in `dataset`.
  public init(dataset: DatasetID, routineID: String) {
    self.init(projectID: dataset.projectID, datasetID: dataset.datasetID, routineID: routineID)
  }

  /// Parses `dataset.routine` or `project.dataset.routine`.
  public init(_ string: String) throws {
    let (project, parts) = try parseResourcePath(string, count: 2, kind: "routine")
    self.init(projectID: project, datasetID: parts[0], routineID: parts[1])
  }

  /// The dataset containing this routine.
  public var dataset: DatasetID { DatasetID(projectID: self.projectID, datasetID: self.datasetID) }

  /// The Standard SQL form, `project.dataset.routine`.
  public var description: String {
    joinResourcePath(self.projectID, [self.datasetID, self.routineID])
  }
}

/// Identifies a BigQuery ML model.
///
/// A `nil` ``projectID`` means the project of the ``BigQueryClient``.
public struct ModelID: Sendable, Hashable, CustomStringConvertible {
  /// The project containing the model, or `nil` for the client project.
  public var projectID: String?

  /// The dataset containing the model.
  public var datasetID: String

  /// The model ID within the dataset.
  public var modelID: String

  /// Creates a model ID.
  public init(projectID: String? = nil, datasetID: String, modelID: String) {
    self.projectID = projectID
    self.datasetID = datasetID
    self.modelID = modelID
  }

  /// Creates the ID of the model `modelID` in `dataset`.
  public init(dataset: DatasetID, modelID: String) {
    self.init(projectID: dataset.projectID, datasetID: dataset.datasetID, modelID: modelID)
  }

  /// Parses `dataset.model` or `project.dataset.model`.
  public init(_ string: String) throws {
    let (project, parts) = try parseResourcePath(string, count: 2, kind: "model")
    self.init(projectID: project, datasetID: parts[0], modelID: parts[1])
  }

  /// The dataset containing this model.
  public var dataset: DatasetID { DatasetID(projectID: self.projectID, datasetID: self.datasetID) }

  /// The Standard SQL form, `project.dataset.model`.
  public var description: String {
    joinResourcePath(self.projectID, [self.datasetID, self.modelID])
  }
}

/// Splits `string` into an optional project and `count` trailing components.
///
/// Components are split on `.` from the right, so domain-scoped projects such as
/// `example.com:project` work. The legacy form `project:dataset[.table]` is also accepted.
func parseResourcePath(_ string: String, count: Int, kind: String) throws -> (String?, [String]) {
  var components = string.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
  if components.count == count, let colon = components[0].lastIndex(of: ":") {
    // Legacy `project:dataset[.table]`.
    let project = String(components[0][..<colon])
    components[0] = String(components[0][components[0].index(after: colon)...])
    components.insert(project, at: 0)
  }
  if components.contains(where: \.isEmpty) {
    throw BigQueryError.invalidArgument("invalid \(kind) ID: \"\(string)\"")
  }
  let project: String?
  let parts: [String]
  if components.count == count {
    project = nil
    parts = components
  } else if components.count > count {
    project = components.dropLast(count).joined(separator: ".")
    parts = Array(components.suffix(count))
  } else {
    throw BigQueryError.invalidArgument("invalid \(kind) ID: \"\(string)\"")
  }
  return (project, parts)
}

func joinResourcePath(_ project: String?, _ parts: [String]) -> String {
  ((project.map { [$0] } ?? []) + parts).joined(separator: ".")
}
