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
@_spi(GoogleCloudInternal) import GoogleWKT

/// What a copy job does.
public struct CopyOperationType: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Copies the tables. The service default.
  public static let copy = CopyOperationType(rawValue: "COPY")
  /// Creates a table snapshot.
  public static let snapshot = CopyOperationType(rawValue: "SNAPSHOT")
  /// Restores a table snapshot to a table.
  public static let restore = CopyOperationType(rawValue: "RESTORE")
  /// Creates a table clone.
  public static let clone = CopyOperationType(rawValue: "CLONE")

  public var description: String { self.rawValue }
}

/// The configuration of a copy job.
public struct CopyJobConfiguration: Sendable, Equatable {
  /// The tables to copy.
  public var sourceTables: [TableID]
  /// The table to write.
  public var destinationTable: TableID
  /// What the job does: copy, snapshot, restore, or clone.
  public var operationType: CopyOperationType?
  /// When the destination table expires, for snapshots.
  public var destinationExpirationTime: Date?
  /// Whether the job may create the destination table.
  public var createDisposition: CreateDisposition?
  /// What the job does when the destination table has data.
  public var writeDisposition: WriteDisposition?
  /// Encryption of the destination table.
  public var destinationEncryption: EncryptionConfiguration?
  /// Labels for the job.
  public var labels: [String: String]
  /// The maximum time the job may run.
  public var jobTimeout: Duration?
  /// The reservation that runs the job.
  public var reservation: String?

  /// Creates a copy configuration.
  public init(
    sourceTables: [TableID], destinationTable: TableID, operationType: CopyOperationType? = nil
  ) {
    self.sourceTables = sourceTables
    self.destinationTable = destinationTable
    self.operationType = operationType
    self.labels = [:]
  }

  /// Creates a configuration that copies one table.
  public init(
    sourceTable: TableID, destinationTable: TableID, operationType: CopyOperationType? = nil
  ) {
    self.init(
      sourceTables: [sourceTable], destinationTable: destinationTable,
      operationType: operationType)
  }

  var common: CommonJobFields {
    CommonJobFields(labels: self.labels, jobTimeout: self.jobTimeout, reservation: self.reservation)
  }
}

// MARK: - Wire conversion

extension CopyJobConfiguration {
  init(
    wire: GoogleCloudBigQueryV2.JobConfigurationTableCopy,
    common: GoogleCloudBigQueryV2.JobConfiguration
  ) {
    // The service reports a single source in `sourceTable` or in `sourceTables`.
    var sources = wire.sourceTables.map(TableID.init(wire:))
    if sources.isEmpty, let source = wire.sourceTable {
      sources = [TableID(wire: source)]
    }
    self.init(
      sourceTables: sources,
      destinationTable: wire.destinationTable.map(TableID.init(wire:))
        ?? TableID(datasetID: "", tableID: ""),
      operationType: specifiedEnumValue(wire.operationType.stringValue).map(
        CopyOperationType.init(rawValue:)))
    self.destinationExpirationTime = wire.destinationExpirationTime.map(Date.init(wire:))
    self.createDisposition = wire.createDisposition.nonEmpty.map(CreateDisposition.init)
    self.writeDisposition = wire.writeDisposition.nonEmpty.map(WriteDisposition.init)
    self.destinationEncryption = wire.destinationEncryptionConfiguration.map(
      EncryptionConfiguration.init(wire:))
    let shared = CommonJobFields(wire: common)
    self.labels = shared.labels
    self.jobTimeout = shared.jobTimeout
    self.reservation = shared.reservation
  }

  var wire: GoogleCloudBigQueryV2.JobConfigurationTableCopy {
    GoogleCloudBigQueryV2.JobConfigurationTableCopy().with {
      $0.sourceTables = self.sourceTables.map(\.wire)
      $0.destinationTable = self.destinationTable.wire
      if let operationType = self.operationType {
        $0.operationType = .init(stringValue: operationType.rawValue)
      }
      $0.destinationExpirationTime = self.destinationExpirationTime.flatMap {
        try? GoogleWKT.WKTTimestamp(date: $0)
      }
      $0.createDisposition = self.createDisposition?.rawValue ?? ""
      $0.writeDisposition = self.writeDisposition?.rawValue ?? ""
      $0.destinationEncryptionConfiguration = self.destinationEncryption?.wire
    }
  }

  func withDefaultProject(_ projectID: String) -> CopyJobConfiguration {
    var copy = self
    copy.sourceTables = copy.sourceTables.map { $0.withDefaultProject(projectID) }
    copy.destinationTable = copy.destinationTable.withDefaultProject(projectID)
    return copy
  }
}
