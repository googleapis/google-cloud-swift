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

/// The configuration of a job: what the job does.
///
/// The four cases are the job types BigQuery has. This enum is closed: a job of a type this
/// library does not know has a `nil` ``Job/configuration`` instead of a new case.
public enum JobConfiguration: Sendable, Equatable {
  /// Runs a query.
  case query(QueryJobConfiguration)
  /// Loads data into a table.
  case load(LoadJobConfiguration)
  /// Exports a table or model to Cloud Storage.
  case extract(ExtractJobConfiguration)
  /// Copies tables.
  case copy(CopyJobConfiguration)
}

/// Whether a job may create its destination table.
public struct CreateDisposition: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Create the table if it does not exist. The service default.
  public static let createIfNeeded = CreateDisposition(rawValue: "CREATE_IF_NEEDED")
  /// Fail if the table does not exist.
  public static let createNever = CreateDisposition(rawValue: "CREATE_NEVER")

  public var description: String { self.rawValue }
}

/// What a job does when its destination table already has data.
public struct WriteDisposition: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Replace the table's data and schema.
  public static let writeTruncate = WriteDisposition(rawValue: "WRITE_TRUNCATE")
  /// Replace the table's data, keeping its schema and constraints.
  public static let writeTruncateData = WriteDisposition(rawValue: "WRITE_TRUNCATE_DATA")
  /// Append to the table.
  public static let writeAppend = WriteDisposition(rawValue: "WRITE_APPEND")
  /// Fail if the table has data.
  public static let writeEmpty = WriteDisposition(rawValue: "WRITE_EMPTY")

  public var description: String { self.rawValue }
}

/// A schema change that a load or query job may make to its destination table.
public struct SchemaUpdateOption: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Allow adding a nullable field.
  public static let allowFieldAddition = SchemaUpdateOption(rawValue: "ALLOW_FIELD_ADDITION")
  /// Allow relaxing a required field to nullable.
  public static let allowFieldRelaxation = SchemaUpdateOption(rawValue: "ALLOW_FIELD_RELAXATION")

  public var description: String { self.rawValue }
}

/// A connection-level property for a query or load job, such as `time_zone` or
/// `session_id`.
public struct ConnectionProperty: Sendable, Hashable {
  /// The property name.
  public var key: String
  /// The property value.
  public var value: String

  /// Creates a connection property.
  public init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  /// Runs the job in an existing session.
  public static func sessionID(_ id: String) -> ConnectionProperty {
    ConnectionProperty(key: "session_id", value: id)
  }

  /// Sets the default time zone of the job.
  public static func timeZone(_ zone: String) -> ConnectionProperty {
    ConnectionProperty(key: "time_zone", value: zone)
  }
}

// MARK: - Wire conversion

extension ConnectionProperty {
  init(wire: GoogleCloudBigQueryV2.ConnectionProperty) {
    self.init(key: wire.key, value: wire.value)
  }

  var wire: GoogleCloudBigQueryV2.ConnectionProperty {
    GoogleCloudBigQueryV2.ConnectionProperty().with {
      $0.key = self.key
      $0.value = self.value
    }
  }
}

/// The fields every job type stores on the shared `JobConfiguration` message.
struct CommonJobFields: Equatable {
  var labels: [String: String] = [:]
  var jobTimeout: Duration?
  var reservation: String?

  init(labels: [String: String], jobTimeout: Duration?, reservation: String?) {
    self.labels = labels
    self.jobTimeout = jobTimeout
    self.reservation = reservation
  }

  init(wire: GoogleCloudBigQueryV2.JobConfiguration) {
    self.labels = wire.labels
    self.jobTimeout = wire.jobTimeoutMs.map { .milliseconds($0) }
    self.reservation = wire.reservation
  }

  func apply(to wire: inout GoogleCloudBigQueryV2.JobConfiguration) {
    wire.labels = self.labels
    wire.jobTimeoutMs = self.jobTimeout?.wholeMilliseconds
    wire.reservation = self.reservation
  }
}

extension JobConfiguration {
  /// Converts a wire configuration, or returns `nil` for a job type this library does not know.
  init?(wire: GoogleCloudBigQueryV2.JobConfiguration) {
    if let query = wire.query {
      self = .query(QueryJobConfiguration(wire: query, common: wire))
    } else if let load = wire.load {
      self = .load(LoadJobConfiguration(wire: load, common: wire))
    } else if let extract = wire.extract {
      self = .extract(ExtractJobConfiguration(wire: extract, common: wire))
    } else if let copy = wire.copy {
      self = .copy(CopyJobConfiguration(wire: copy, common: wire))
    } else {
      return nil
    }
  }

  var wire: GoogleCloudBigQueryV2.JobConfiguration {
    var wire = GoogleCloudBigQueryV2.JobConfiguration()
    switch self {
    case .query(let query):
      wire.query = query.wire
      wire.dryRun = query.dryRun ? true : nil
      query.common.apply(to: &wire)
    case .load(let load):
      wire.load = load.wire
      load.common.apply(to: &wire)
    case .extract(let extract):
      wire.extract = extract.wire
      extract.common.apply(to: &wire)
    case .copy(let copy):
      wire.copy = copy.wire
      copy.common.apply(to: &wire)
    }
    return wire
  }

  /// Fills a missing project in every table and dataset reference with `projectID`.
  ///
  /// An explicit project is never replaced.
  func withDefaultProject(_ projectID: String) -> JobConfiguration {
    switch self {
    case .query(let query): return .query(query.withDefaultProject(projectID))
    case .load(let load): return .load(load.withDefaultProject(projectID))
    case .extract(let extract): return .extract(extract.withDefaultProject(projectID))
    case .copy(let copy): return .copy(copy.withDefaultProject(projectID))
    }
  }
}

extension TableID {
  /// This ID with `projectID` filled in when it has no project.
  func withDefaultProject(_ projectID: String) -> TableID {
    var copy = self
    if copy.projectID == nil { copy.projectID = projectID }
    return copy
  }
}

extension DatasetID {
  /// This ID with `projectID` filled in when it has no project.
  func withDefaultProject(_ projectID: String) -> DatasetID {
    var copy = self
    if copy.projectID == nil { copy.projectID = projectID }
    return copy
  }
}

extension ModelID {
  /// This ID with `projectID` filled in when it has no project.
  func withDefaultProject(_ projectID: String) -> ModelID {
    var copy = self
    if copy.projectID == nil { copy.projectID = projectID }
    return copy
  }
}
