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

/// A BigQuery table, view, materialized view, external table, or snapshot.
///
/// The kind of table follows from which definition is set: ``view``,
/// ``materializedView``, ``externalDataConfiguration``, or none of them for a
/// standard table. Snapshots and clones are created with copy jobs and carry
/// ``snapshotDefinition`` or ``cloneDefinition``.
///
/// Properties marked *output only* are set by the server and ignored by
/// `createTable` and `updateTable`. On `updateTable`, a `nil` property is left
/// unchanged; clear a property by passing it in `clearing:` (see
/// ``Table/Field``).
///
/// `listTables` returns partial tables: only ``id``, ``friendlyName``,
/// ``type``, ``labels``, ``creationTime``, ``expirationTime``,
/// ``timePartitioning``, ``rangePartitioning``, ``clustering``,
/// ``requirePartitionFilter``, and ``generatedID`` are populated. Use `getTable` for the full metadata.
public struct Table: Sendable, Equatable {
  /// The table's ID. A `nil` project means the client's project.
  public var id: TableID
  /// A descriptive name.
  public var friendlyName: String?
  /// A description.
  public var description: String?
  /// Labels. On update, the given keys are added or changed and other keys
  /// are kept; clear keys with ``Field/label(_:)`` or ``Field/labels``.
  public var labels: [String: String]?
  /// When the table expires and is deleted.
  public var expirationTime: Date?
  /// The table's schema.
  public var schema: Schema?
  /// Time-based partitioning.
  public var timePartitioning: TimePartitioning?
  /// Integer-range partitioning.
  public var rangePartitioning: RangePartitioning?
  /// Clustering columns.
  public var clustering: Clustering?
  /// Customer-managed encryption.
  public var encryption: EncryptionConfiguration?
  /// Whether queries must filter on the partitioning column.
  public var requirePartitionFilter: Bool?
  /// Makes the table a logical view.
  public var view: ViewDefinition?
  /// Makes the table a materialized view.
  public var materializedView: MaterializedViewDefinition?
  /// Makes the table an external table.
  public var externalDataConfiguration: ExternalDataConfiguration?
  /// Makes the table a BigLake managed (Apache Iceberg) table.
  public var bigLakeConfiguration: BigLakeConfiguration?
  /// The base table of a snapshot. Output only.
  public var snapshotDefinition: SnapshotDefinition?
  /// The base table of a clone. Output only.
  public var cloneDefinition: CloneDefinition?
  /// Primary and foreign keys.
  public var tableConstraints: TableConstraints?
  /// The default collation of new STRING fields, for example `und:ci`.
  public var defaultCollation: String?
  /// The default rounding mode of new NUMERIC and BIGNUMERIC fields.
  public var defaultRoundingMode: GoogleCloudBigQuery.Field.RoundingMode?
  /// The maximum staleness of data that queries of a materialized view or
  /// BigLake table may return, as an INTERVAL literal such as `0-0 0 4:0:0`.
  public var maxStaleness: String?
  /// Tags attached to the table, keyed by namespaced tag key
  /// (`{org or project}/{key}`) with the short tag value.
  public var resourceTags: [String: String]?

  /// The kind of table. Output only.
  public var type: TableType?
  /// The resource's HTTP ETag. Output only. Pass it as `ifMatch:` to
  /// `updateTable` for optimistic concurrency.
  public var etag: String?
  /// The server's ID of the table, `project:dataset.table`. Output only.
  public var generatedID: String?
  /// The URL of the resource. Output only.
  public var selfLink: String?
  /// When the table was created. Output only.
  public var creationTime: Date?
  /// When the table was last modified. Output only.
  public var lastModifiedTime: Date?
  /// The location of the table's dataset. Output only.
  public var location: String?
  /// The number of rows, excluding the streaming buffer. Output only.
  public var numRows: UInt64?
  /// The size of the table in bytes, excluding the streaming buffer. Output
  /// only.
  public var numBytes: Int64?
  /// The bytes in long-term storage. Output only.
  public var numLongTermBytes: Int64?
  /// The physical bytes, including time travel. Output only.
  public var numPhysicalBytes: Int64?
  /// The physical bytes used by time travel. Output only.
  public var numTimeTravelPhysicalBytes: Int64?
  /// The total logical bytes. Output only.
  public var numTotalLogicalBytes: Int64?
  /// The logical bytes less than 90 days old. Output only.
  public var numActiveLogicalBytes: Int64?
  /// The logical bytes more than 90 days old. Output only.
  public var numLongTermLogicalBytes: Int64?
  /// The total physical bytes. Output only.
  public var numTotalPhysicalBytes: Int64?
  /// The physical bytes less than 90 days old. Output only.
  public var numActivePhysicalBytes: Int64?
  /// The physical bytes more than 90 days old. Output only.
  public var numLongTermPhysicalBytes: Int64?
  /// The number of partitions. Output only.
  public var numPartitions: Int64?
  /// The streaming buffer, if the table has one. Output only.
  public var streamingBuffer: StreamingBuffer?

  /// Creates a table. Set a definition (``view``,
  /// ``materializedView``, or ``externalDataConfiguration``) to create
  /// something other than a standard table.
  public init(
    id: TableID,
    schema: Schema? = nil,
    friendlyName: String? = nil,
    description: String? = nil,
    labels: [String: String]? = nil
  ) {
    self.id = id
    self.schema = schema
    self.friendlyName = friendlyName
    self.description = description
    self.labels = labels
  }
}

extension Table {
  /// A table property that `updateTable` can clear.
  ///
  /// Clearing sends an explicit JSON `null` for the property.
  public struct Field: Sendable, Hashable {
    /// The dot-separated JSON path of the property.
    let path: String

    /// ``Table/friendlyName``.
    public static let friendlyName = Field(path: "friendlyName")
    /// ``Table/description``.
    public static let description = Field(path: "description")
    /// ``Table/expirationTime``: the table no longer expires.
    public static let expirationTime = Field(path: "expirationTime")
    /// All of ``Table/labels``.
    public static let labels = Field(path: "labels")
    /// ``Table/timePartitioning``'s expiration: partitions no longer expire.
    public static let partitionExpiration = Field(path: "timePartitioning.expirationMs")
    /// ``Table/clustering``: the table is no longer clustered.
    public static let clustering = Field(path: "clustering")
    /// ``Table/defaultCollation``.
    public static let defaultCollation = Field(path: "defaultCollation")
    /// ``Table/tableConstraints``: removes all keys.
    public static let tableConstraints = Field(path: "tableConstraints")
    /// The primary key in ``Table/tableConstraints``.
    public static let primaryKey = Field(path: "tableConstraints.primaryKey")
    /// All of ``Table/resourceTags``.
    public static let resourceTags = Field(path: "resourceTags")

    /// One key of ``Table/labels``.
    public static func label(_ key: String) -> Field {
      Field(path: "labels.\(key)")
    }

    /// One key of ``Table/resourceTags``.
    ///
    /// The key must not contain `.`, which separates JSON path components: for a tag key
    /// whose parent is a domain-scoped project (`example.com:p/env`), clear all
    /// ``resourceTags`` and set the others again instead.
    public static func resourceTag(_ key: String) -> Field {
      Field(path: "resourceTags.\(key)")
    }
  }
}

/// Information about a table's streaming buffer.
public struct StreamingBuffer: Sendable, Hashable {
  /// An estimate of the rows in the buffer.
  public var estimatedRows: UInt64?
  /// An estimate of the bytes in the buffer.
  public var estimatedBytes: UInt64?
  /// The time of the oldest entry in the buffer.
  public var oldestEntryTime: Date?

  /// Creates streaming buffer information.
  public init(
    estimatedRows: UInt64? = nil, estimatedBytes: UInt64? = nil, oldestEntryTime: Date? = nil
  ) {
    self.estimatedRows = estimatedRows
    self.estimatedBytes = estimatedBytes
    self.oldestEntryTime = oldestEntryTime
  }
}

// MARK: - Wire conversions

extension Table {
  init(wire: GoogleCloudBigQueryV2.Table) {
    self.init(
      id: wire.tableReference.map(TableID.init(wire:)) ?? TableID(datasetID: "", tableID: ""),
      schema: wire.schema.map(Schema.init(wire:)),
      friendlyName: wire.friendlyName,
      description: wire.description,
      labels: wire.labels.isEmpty ? nil : wire.labels)
    expirationTime = wire.expirationTime.flatMap(Date.init(millisecondsSinceEpoch:))
    timePartitioning = wire.timePartitioning.map(TimePartitioning.init(wire:))
    rangePartitioning = wire.rangePartitioning.map(RangePartitioning.init(wire:))
    clustering = wire.clustering.map(Clustering.init(wire:))
    encryption = wire.encryptionConfiguration.map(EncryptionConfiguration.init(wire:))
    requirePartitionFilter = wire.requirePartitionFilter
    view = wire.view.map(ViewDefinition.init(wire:))
    materializedView = wire.materializedView.map(MaterializedViewDefinition.init(wire:))
    externalDataConfiguration = wire.externalDataConfiguration.map(
      ExternalDataConfiguration.init(wire:))
    bigLakeConfiguration = wire.biglakeConfiguration.map(BigLakeConfiguration.init(wire:))
    snapshotDefinition = wire.snapshotDefinition.flatMap(SnapshotDefinition.init(wire:))
    cloneDefinition = wire.cloneDefinition.flatMap(CloneDefinition.init(wire:))
    tableConstraints = wire.tableConstraints.map(TableConstraints.init(wire:))
    defaultCollation = wire.defaultCollation
    defaultRoundingMode =
      wire.defaultRoundingMode == .unspecified
      ? nil
      : GoogleCloudBigQuery.Field.RoundingMode(rawValue: wire.defaultRoundingMode.stringValue ?? "")
    maxStaleness = wire.maxStaleness.nonEmpty
    resourceTags = wire.resourceTags.isEmpty ? nil : wire.resourceTags
    type = wire.type.nonEmpty.map(TableType.init(rawValue:))
    etag = wire.etag.nonEmpty
    generatedID = wire.id.nonEmpty
    selfLink = wire.selfLink.nonEmpty
    creationTime = Date(millisecondsSinceEpoch: wire.creationTime)
    lastModifiedTime = Date(millisecondsSinceEpoch: Int64(clamping: wire.lastModifiedTime))
    location = wire.location.nonEmpty
    numRows = wire.numRows
    numBytes = wire.numBytes
    numLongTermBytes = wire.numLongTermBytes
    numPhysicalBytes = wire.numPhysicalBytes
    numTimeTravelPhysicalBytes = wire.numTimeTravelPhysicalBytes
    numTotalLogicalBytes = wire.numTotalLogicalBytes
    numActiveLogicalBytes = wire.numActiveLogicalBytes
    numLongTermLogicalBytes = wire.numLongTermLogicalBytes
    numTotalPhysicalBytes = wire.numTotalPhysicalBytes
    numActivePhysicalBytes = wire.numActivePhysicalBytes
    numLongTermPhysicalBytes = wire.numLongTermPhysicalBytes
    numPartitions = wire.numPartitions
    streamingBuffer = wire.streamingBuffer.map(StreamingBuffer.init(wire:))
  }

  /// The request body for `tables.insert` and `tables.patch`.
  ///
  /// Output-only properties are not sent. When the external configuration
  /// carries a schema, it is sent as the table schema, where BigQuery expects
  /// it for permanent external tables (behavior doc §4 "Tables"; Δ in design
  /// §7: `schema` is kept when the external configuration has none).
  var wire: GoogleCloudBigQueryV2.Table {
    .init().with {
      $0.tableReference = id.wire
      $0.friendlyName = friendlyName
      $0.description = description
      $0.labels = labels ?? [:]
      $0.expirationTime = expirationTime.map(\.millisecondsSinceEpoch)
      $0.schema = schema?.wire
      $0.timePartitioning = timePartitioning?.wire
      $0.rangePartitioning = rangePartitioning?.wire
      $0.clustering = clustering?.wire
      $0.encryptionConfiguration = encryption?.wire
      $0.requirePartitionFilter = requirePartitionFilter
      $0.view = view?.wire
      $0.materializedView = materializedView?.wire
      if var external = externalDataConfiguration?.wire {
        if let externalSchema = external.schema {
          $0.schema = externalSchema
          external.schema = nil
        }
        $0.externalDataConfiguration = external
      }
      $0.biglakeConfiguration = bigLakeConfiguration?.wire
      $0.tableConstraints = tableConstraints?.wire
      $0.defaultCollation = defaultCollation
      if let defaultRoundingMode {
        $0.defaultRoundingMode = .init(stringValue: defaultRoundingMode.rawValue)
      }
      $0.maxStaleness = maxStaleness ?? ""
      $0.resourceTags = resourceTags ?? [:]
    }
  }

  /// The JSON body for `tables.insert` and `tables.patch`, with `clearing` sent as `null`.
  ///
  /// The proto3 defaults of output-only and unset scalar fields are omitted, so a PATCH never
  /// sends a value the caller did not set (design §5).
  func requestBody(clearing: Set<Field> = []) throws -> Data {
    var omitting = [
      "kind", "etag", "id", "selfLink", "type", "creationTime", "lastModifiedTime", "location",
      "managedTableType", "materializedView.lastRefreshTime",
    ]
    if maxStaleness == nil { omitting.append("maxStaleness") }
    if defaultRoundingMode == nil { omitting.append("defaultRoundingMode") }
    return try RequestBody.json(
      wire,
      setting: Dictionary(uniqueKeysWithValues: clearing.map { ($0.path, JSONOverride.null) }),
      omitting: omitting)
  }

  /// Fills a `nil` project in the table ID and in referenced tables.
  func resolved(projectID: String) -> Table {
    var copy = self
    if copy.id.projectID == nil {
      copy.id.projectID = projectID
    }
    copy.tableConstraints = copy.tableConstraints?.resolved(projectID: projectID)
    return copy
  }
}

extension StreamingBuffer {
  init(wire: GoogleCloudBigQueryV2.Streamingbuffer) {
    // The fields are proto3 scalars: 0 means the server did not send them
    // (U.StandardTableDefinition.03).
    self.init(
      estimatedRows: wire.estimatedRows == 0 ? nil : wire.estimatedRows,
      estimatedBytes: wire.estimatedBytes == 0 ? nil : wire.estimatedBytes,
      oldestEntryTime: Date(millisecondsSinceEpoch: Int64(clamping: wire.oldestEntryTime)))
  }
}
