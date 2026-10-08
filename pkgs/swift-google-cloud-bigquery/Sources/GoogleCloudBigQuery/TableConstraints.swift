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

/// The primary and foreign keys of a table.
///
/// BigQuery does not enforce these constraints; the query optimizer uses them.
public struct TableConstraints: Sendable, Hashable {
  /// The table's primary key.
  public var primaryKey: PrimaryKey?
  /// The table's foreign keys.
  public var foreignKeys: [ForeignKey]

  /// Creates table constraints.
  public init(primaryKey: PrimaryKey? = nil, foreignKeys: [ForeignKey] = []) {
    self.primaryKey = primaryKey
    self.foreignKeys = foreignKeys
  }
}

/// The primary key of a table.
public struct PrimaryKey: Sendable, Hashable {
  /// The columns that make up the key.
  public var columns: [String]

  /// Creates a primary key over `columns`.
  public init(columns: [String]) {
    self.columns = columns
  }
}

/// A foreign key of a table.
public struct ForeignKey: Sendable, Hashable {
  /// The name of the key.
  public var name: String?
  /// The table that the key references.
  public var referencedTable: TableID
  /// The pairs of referencing and referenced columns.
  public var columnReferences: [ColumnReference]

  /// Creates a foreign key.
  public init(name: String? = nil, referencedTable: TableID, columnReferences: [ColumnReference]) {
    self.name = name
    self.referencedTable = referencedTable
    self.columnReferences = columnReferences
  }
}

/// A pair of columns in a foreign key.
public struct ColumnReference: Sendable, Hashable {
  /// The column in the table that has the foreign key.
  public var referencingColumn: String
  /// The column in the referenced table.
  public var referencedColumn: String

  /// Creates a column pair.
  public init(referencingColumn: String, referencedColumn: String) {
    self.referencingColumn = referencingColumn
    self.referencedColumn = referencedColumn
  }
}

// MARK: - Wire conversions

extension TableConstraints {
  init(wire: GoogleCloudBigQueryV2.TableConstraints) {
    self.init(
      primaryKey: wire.primaryKey.map { PrimaryKey(columns: $0.columns) },
      foreignKeys: wire.foreignKeys.map(ForeignKey.init(wire:)))
  }

  var wire: GoogleCloudBigQueryV2.TableConstraints {
    .init().with {
      $0.primaryKey = primaryKey.map { key in .init().with { $0.columns = key.columns } }
      $0.foreignKeys = foreignKeys.map(\.wire)
    }
  }

  /// Fills a `nil` project in referenced tables.
  func resolved(projectID: String) -> TableConstraints {
    var copy = self
    for index in copy.foreignKeys.indices
    where copy.foreignKeys[index].referencedTable.projectID == nil {
      copy.foreignKeys[index].referencedTable.projectID = projectID
    }
    return copy
  }
}

extension ForeignKey {
  init(wire: GoogleCloudBigQueryV2.ForeignKey) {
    self.init(
      name: wire.name.nonEmpty,
      referencedTable: wire.referencedTable.map(TableID.init(wire:))
        ?? TableID(datasetID: "", tableID: ""),
      columnReferences: wire.columnReferences.map {
        ColumnReference(
          referencingColumn: $0.referencingColumn, referencedColumn: $0.referencedColumn)
      })
  }

  var wire: GoogleCloudBigQueryV2.ForeignKey {
    .init().with {
      $0.name = name ?? ""
      $0.referencedTable = referencedTable.wire
      $0.columnReferences = columnReferences.map { reference in
        .init().with {
          $0.referencingColumn = reference.referencingColumn
          $0.referencedColumn = reference.referencedColumn
        }
      }
    }
  }
}
