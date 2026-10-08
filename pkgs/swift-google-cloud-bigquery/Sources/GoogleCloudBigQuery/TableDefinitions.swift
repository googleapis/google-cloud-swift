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

/// The kind of a table, as reported by the server.
public struct TableType: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// A table whose data is stored in BigQuery.
  public static let table = TableType(rawValue: "TABLE")
  /// A logical view defined by a query (``Table/view``).
  public static let view = TableType(rawValue: "VIEW")
  /// A materialized view (``Table/materializedView``).
  public static let materializedView = TableType(rawValue: "MATERIALIZED_VIEW")
  /// A table over external data (``Table/externalDataConfiguration``).
  public static let external = TableType(rawValue: "EXTERNAL")
  /// A table snapshot (``Table/snapshotDefinition``).
  public static let snapshot = TableType(rawValue: "SNAPSHOT")
  /// A BigQuery ML model listed as a table.
  public static let model = TableType(rawValue: "MODEL")
}

/// How much table metadata `getTable` returns.
public struct TableMetadataView: RawRepresentable, Sendable, Hashable {
  /// The wire value.
  public var rawValue: String
  /// Creates a value from its wire representation.
  public init(rawValue: String) { self.rawValue = rawValue }
  /// The server default, which is ``basic``.
  public static let unspecified = TableMetadataView(rawValue: "TABLE_METADATA_VIEW_UNSPECIFIED")
  /// Schema, partitioning, and other basic metadata, without storage
  /// statistics.
  public static let basic = TableMetadataView(rawValue: "BASIC")
  /// Basic metadata plus storage statistics such as `numBytes` and `numRows`.
  public static let storageStats = TableMetadataView(rawValue: "STORAGE_STATS")
  /// All metadata, including the streaming buffer.
  public static let full = TableMetadataView(rawValue: "FULL")
}

/// The definition of a logical view.
public struct ViewDefinition: Sendable, Hashable {
  /// The query that defines the view.
  public var query: String
  /// User-defined function resources used by the query.
  public var userDefinedFunctions: [UserDefinedFunction]
  /// Whether ``query`` uses legacy SQL. The client always sends this value;
  /// it defaults to `false` (GoogleSQL).
  public var useLegacySQL: Bool

  /// Creates a view definition.
  public init(
    query: String, userDefinedFunctions: [UserDefinedFunction] = [], useLegacySQL: Bool = false
  ) {
    self.query = query
    self.userDefinedFunctions = userDefinedFunctions
    self.useLegacySQL = useLegacySQL
  }
}

/// The definition of a materialized view.
public struct MaterializedViewDefinition: Sendable, Hashable {
  /// The query that defines the materialized view.
  public var query: String
  /// Whether BigQuery refreshes the materialized view automatically.
  public var enableRefresh: Bool?
  /// The maximum interval between automatic refreshes.
  public var refreshInterval: Duration?
  /// Whether the query may use SQL features that need a full refresh.
  public var allowNonIncrementalDefinition: Bool?
  /// When the materialized view was last refreshed. Output only.
  public var lastRefreshTime: Date?

  /// Creates a materialized view definition.
  public init(
    query: String, enableRefresh: Bool? = nil, refreshInterval: Duration? = nil,
    allowNonIncrementalDefinition: Bool? = nil
  ) {
    self.query = query
    self.enableRefresh = enableRefresh
    self.refreshInterval = refreshInterval
    self.allowNonIncrementalDefinition = allowNonIncrementalDefinition
  }
}

/// Describes a table snapshot: the table it was taken from, and when. Output only.
///
/// Snapshots are created with a copy job whose operation type is snapshot, or with DDL.
public struct SnapshotDefinition: Sendable, Hashable {
  /// The table the snapshot was taken from.
  public var baseTable: TableID
  /// The time of the base table that the snapshot captures.
  public var snapshotTime: Date

  /// Creates a snapshot definition.
  public init(baseTable: TableID, snapshotTime: Date) {
    self.baseTable = baseTable
    self.snapshotTime = snapshotTime
  }
}

/// Describes a table clone: the table it was cloned from, and when. Output only.
///
/// Clones are created with a copy job whose operation type is clone, or with DDL.
public struct CloneDefinition: Sendable, Hashable {
  /// The table the clone was created from.
  public var baseTable: TableID
  /// The time of the base table that the clone captures.
  public var cloneTime: Date

  /// Creates a clone definition.
  public init(baseTable: TableID, cloneTime: Date) {
    self.baseTable = baseTable
    self.cloneTime = cloneTime
  }
}

// MARK: - Wire conversions

extension ViewDefinition {
  init(wire: GoogleCloudBigQueryV2.ViewDefinition) {
    self.init(
      query: wire.query,
      userDefinedFunctions: wire.userDefinedFunctionResources.compactMap(
        UserDefinedFunction.init(wire:)),
      // An absent value means legacy SQL, the server default (design §2).
      useLegacySQL: wire.useLegacySql ?? true)
  }

  var wire: GoogleCloudBigQueryV2.ViewDefinition {
    .init().with {
      $0.query = query
      $0.userDefinedFunctionResources = userDefinedFunctions.map(\.wire)
      $0.useLegacySql = useLegacySQL
    }
  }
}

extension MaterializedViewDefinition {
  init(wire: GoogleCloudBigQueryV2.MaterializedViewDefinition) {
    self.init(
      query: wire.query, enableRefresh: wire.enableRefresh,
      refreshInterval: wire.refreshIntervalMs.map { .milliseconds($0) },
      allowNonIncrementalDefinition: wire.allowNonIncrementalDefinition)
    lastRefreshTime = Date(millisecondsSinceEpoch: wire.lastRefreshTime)
  }

  var wire: GoogleCloudBigQueryV2.MaterializedViewDefinition {
    .init().with {
      $0.query = query
      $0.enableRefresh = enableRefresh
      $0.refreshIntervalMs = refreshInterval.map { UInt64(max(0, $0.wholeMilliseconds)) }
      $0.allowNonIncrementalDefinition = allowNonIncrementalDefinition
    }
  }
}

extension SnapshotDefinition {
  init?(wire: GoogleCloudBigQueryV2.SnapshotDefinition) {
    guard let base = wire.baseTableReference, let time = wire.snapshotTime else { return nil }
    self.init(baseTable: TableID(wire: base), snapshotTime: Date(wire: time))
  }
}

extension CloneDefinition {
  init?(wire: GoogleCloudBigQueryV2.CloneDefinition) {
    guard let base = wire.baseTableReference, let time = wire.cloneTime else { return nil }
    self.init(baseTable: TableID(wire: base), cloneTime: Date(wire: time))
  }
}
