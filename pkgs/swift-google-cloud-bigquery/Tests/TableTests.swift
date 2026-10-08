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

import Foundation
import GoogleCloudBigQueryV2
import Testing

@testable import GoogleCloudBigQuery

/// The public types, which `GoogleCloudBigQueryV2` also declares.
private typealias Table = GoogleCloudBigQuery.Table
private typealias TableConstraints = GoogleCloudBigQuery.TableConstraints
private typealias PrimaryKey = GoogleCloudBigQuery.PrimaryKey
private typealias ForeignKey = GoogleCloudBigQuery.ForeignKey
private typealias ColumnReference = GoogleCloudBigQuery.ColumnReference
private typealias ViewDefinition = GoogleCloudBigQuery.ViewDefinition
private typealias MaterializedViewDefinition = GoogleCloudBigQuery.MaterializedViewDefinition
private typealias SnapshotDefinition = GoogleCloudBigQuery.SnapshotDefinition
private typealias CloneDefinition = GoogleCloudBigQuery.CloneDefinition
private typealias TimePartitioning = GoogleCloudBigQuery.TimePartitioning
private typealias ExternalDataConfiguration = GoogleCloudBigQuery.ExternalDataConfiguration

@Suite struct TableTests {
  /// Every input field of a table, as the service sends and receives it.
  static let inputJSON = #"""
    {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"},
     "friendlyName": "Friendly", "description": "A table", "labels": {"k": "v"},
     "expirationTime": "1700000000000",
     "schema": {"fields": [{"name": "ts", "type": "TIMESTAMP", "mode": "REQUIRED"},
       {"name": "n", "type": "INT64", "mode": "NULLABLE"}]},
     "timePartitioning": {"type": "DAY", "field": "ts", "expirationMs": "86400000"},
     "clustering": {"fields": ["n"]},
     "encryptionConfiguration": {"kmsKeyName": "projects/p/locations/us/keyRings/r/cryptoKeys/k"},
     "requirePartitionFilter": true,
     "tableConstraints": {"primaryKey": {"columns": ["n"]},
       "foreignKeys": [{"name": "fk", "referencedTable": {"projectId": "p", "datasetId": "d",
         "tableId": "other"}, "columnReferences": [{"referencingColumn": "n",
         "referencedColumn": "id"}]}]},
     "defaultCollation": "und:ci", "defaultRoundingMode": "ROUND_HALF_EVEN",
     "maxStaleness": "0-0 0 4:0:0", "resourceTags": {"123/env": "prod"}}
    """#

  /// The output-only fields of a table.
  static let outputJSON = #"""
    {"type": "TABLE", "etag": "e1", "id": "p:d.t", "selfLink": "https://x/t",
     "creationTime": "1600000000000", "lastModifiedTime": "1600000001000", "location": "US",
     "numRows": "10", "numBytes": "100", "numLongTermBytes": "1", "numPhysicalBytes": "2",
     "numTimeTravelPhysicalBytes": "3", "numTotalLogicalBytes": "4", "numActiveLogicalBytes": "5",
     "numLongTermLogicalBytes": "6", "numTotalPhysicalBytes": "7", "numActivePhysicalBytes": "8",
     "numLongTermPhysicalBytes": "9", "numPartitions": "11",
     "streamingBuffer": {"estimatedRows": "12", "estimatedBytes": "13",
       "oldestEntryTime": "1600000002000"}}
    """#

  /// `inputJSON` and `outputJSON` combined.
  static func fullJSON() throws -> String {
    let full = try WireJSON.object(inputJSON).mutableCopy() as! NSMutableDictionary
    full.addEntries(from: try WireJSON.object(outputJSON) as! [AnyHashable: Any])
    return String(decoding: try JSONSerialization.data(withJSONObject: full), as: UTF8.self)
  }

  fileprivate static func decode(_ json: String) throws -> Table {
    Table(wire: try WireJSON.decode(json, as: GoogleCloudBigQueryV2.Table.self))
  }

  /// `json` decoded as a wire table and encoded again, with the proto3 defaults it implies.
  static func wireObject(_ json: String) throws -> NSDictionary {
    try WireJSON.object(WireJSON.decode(json, as: GoogleCloudBigQueryV2.Table.self))
  }

  /// The `tables.insert` request body of `table`, as a JSON object.
  fileprivate static func body(_ table: Table) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: try table.requestBody()) as? NSDictionary ?? [:]
  }

  // Baseline: U.TableInfo.01, U.Table.03, U.StandardTableDefinition.01
  @Test func tableRoundTripsEveryField() throws {
    let table = try Self.decode(try Self.fullJSON())

    #expect(table.id == TableID(projectID: "p", datasetID: "d", tableID: "t"))
    #expect(table.friendlyName == "Friendly")
    #expect(table.description == "A table")
    #expect(table.labels == ["k": "v"])
    #expect(table.expirationTime == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(
      table.schema
        == Schema([
          Field("ts", .timestamp, mode: .required), Field("n", .int64, mode: .nullable),
        ]))
    #expect(
      table.timePartitioning
        == TimePartitioning(type: .day, field: "ts", expiration: .seconds(86400))
    )
    #expect(table.clustering == Clustering(fields: ["n"]))
    #expect(table.encryption?.kmsKeyName == "projects/p/locations/us/keyRings/r/cryptoKeys/k")
    #expect(table.requirePartitionFilter == true)
    #expect(table.tableConstraints?.primaryKey == PrimaryKey(columns: ["n"]))
    #expect(table.defaultCollation == "und:ci")
    #expect(table.defaultRoundingMode == .roundHalfEven)
    #expect(table.maxStaleness == "0-0 0 4:0:0")
    #expect(table.resourceTags == ["123/env": "prod"])

    #expect(table.type == .table)
    #expect(table.etag == "e1")
    #expect(table.generatedID == "p:d.t")
    #expect(table.selfLink == "https://x/t")
    #expect(table.creationTime == Date(timeIntervalSince1970: 1_600_000_000))
    #expect(table.lastModifiedTime == Date(timeIntervalSince1970: 1_600_000_001))
    #expect(table.location == "US")
    #expect(table.numRows == 10)
    #expect(table.numBytes == 100)
    #expect(table.numLongTermBytes == 1)
    #expect(table.numPhysicalBytes == 2)
    #expect(table.numTimeTravelPhysicalBytes == 3)
    #expect(table.numTotalLogicalBytes == 4)
    #expect(table.numActiveLogicalBytes == 5)
    #expect(table.numLongTermLogicalBytes == 6)
    #expect(table.numTotalPhysicalBytes == 7)
    #expect(table.numActivePhysicalBytes == 8)
    #expect(table.numLongTermPhysicalBytes == 9)
    #expect(table.numPartitions == 11)
    #expect(
      table.streamingBuffer
        == StreamingBuffer(
          estimatedRows: 12, estimatedBytes: 13,
          oldestEntryTime: Date(timeIntervalSince1970: 1_600_000_002)))

    // The request carries every input field and no output field.
    #expect(try WireJSON.object(table.wire) == Self.wireObject(Self.inputJSON))
    let body = try Self.body(table)
    for key in ["type", "etag", "id", "selfLink", "creationTime", "location", "numRows"] {
      #expect(body[key] == nil, "\(key)")
    }
    #expect(body["maxStaleness"] as? String == "0-0 0 4:0:0")
    #expect(body["defaultRoundingMode"] as? String == "ROUND_HALF_EVEN")
  }

  // Baseline: U.TableInfo.01
  @Test func rangePartitionedTableRoundTrips() throws {
    let json = #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"},
       "rangePartitioning": {"field": "n", "range": {"start": "1", "end": "10", "interval": "2"}}}
      """#
    let table = try Self.decode(json)
    #expect(
      table.rangePartitioning
        == RangePartitioning(field: "n", range: .init(start: 1, end: 10, interval: 2)))
    #expect(try WireJSON.object(table.wire) == Self.wireObject(json))
  }

  // Baseline: U.TableInfo.02
  @Test func resolvedFillsMissingProjectsOnly() {
    var table = Table(id: TableID(datasetID: "d", tableID: "t"))
    table.tableConstraints = TableConstraints(foreignKeys: [
      ForeignKey(
        referencedTable: TableID(datasetID: "d", tableID: "a"),
        columnReferences: [ColumnReference(referencingColumn: "x", referencedColumn: "y")]),
      ForeignKey(
        referencedTable: TableID(projectID: "other", datasetID: "d", tableID: "b"),
        columnReferences: [ColumnReference(referencingColumn: "x", referencedColumn: "y")]),
    ])
    let resolved = table.resolved(projectID: "p")
    #expect(resolved.id.projectID == "p")
    #expect(
      resolved.tableConstraints?.foreignKeys.map(\.referencedTable.projectID) == ["p", "other"])

    let explicit = Table(id: TableID(projectID: "mine", datasetID: "d", tableID: "t"))
    #expect(explicit.resolved(projectID: "p").id.projectID == "mine")
  }

  // Baseline: U.StandardTableDefinition.02
  @Test func unknownPartitionTypeIsPreserved() throws {
    let json = #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"},
       "timePartitioning": {"type": "DECADE"}}
      """#
    let table = try Self.decode(json)
    #expect(table.timePartitioning?.type == TimePartitioning.PartitionType(rawValue: "DECADE"))
    #expect(try WireJSON.object(table.wire) == Self.wireObject(json))
  }

  // Baseline: U.StandardTableDefinition.03
  @Test func streamingBufferWithoutFieldsDecodes() throws {
    let table = try Self.decode(
      #"{"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "t"}, "streamingBuffer": {}}"#
    )
    #expect(table.streamingBuffer == StreamingBuffer())
    #expect(try Self.body(table)["streamingBuffer"] == nil)
  }

  // Baseline: U.ModelTableDefinition.01
  @Test func modelTypeDecodes() throws {
    let table = try Self.decode(
      #"{"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "m"}, "type": "MODEL"}"#)
    #expect(table.type == .model)
    #expect(try Self.body(table)["type"] == nil)
  }

  // Baseline: U.TableInfo.01
  @Test(arguments: [
    ("TABLE", TableType.table), ("VIEW", .view), ("MATERIALIZED_VIEW", .materializedView),
    ("EXTERNAL", .external), ("SNAPSHOT", .snapshot), ("MODEL", .model),
  ])
  func tableTypesUseWireNames(wire: String, type: TableType) {
    #expect(type.rawValue == wire)
  }

  // Baseline: U.ViewDefinition.01
  @Test func viewDefinitionRoundTrips() throws {
    let json = #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "v"},
       "view": {"query": "SELECT 1", "useLegacySql": false,
         "userDefinedFunctionResources": [{"resourceUri": "gs://b/f.js"},
           {"inlineCode": "var x = 1;"}]}}
      """#
    let table = try Self.decode(json)
    #expect(
      table.view
        == ViewDefinition(
          query: "SELECT 1", userDefinedFunctions: [.fromURI("gs://b/f.js"), .inline("var x = 1;")])
    )
    #expect(try WireJSON.object(table.wire) == Self.wireObject(json))
  }

  // Design: §5 (proto3 defaults on PATCH)
  @Test func unsetScalarsAreNotSent() throws {
    let body = try Self.body(Table(id: TableID(projectID: "p", datasetID: "d", tableID: "t")))
    #expect(body.allKeys as? [String] == ["tableReference"])
  }

  // Design: §2 S§3 #1
  @Test func viewDefinitionDefaultsToStandardSQLButReadsAbsentAsLegacy() throws {
    #expect(ViewDefinition(query: "SELECT 1").useLegacySQL == false)
    let wire = try WireJSON.object(ViewDefinition(query: "SELECT 1").wire)
    #expect(wire["useLegacySql"] as? Bool == false)
    let decoded = try Self.decode(
      #"{"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "v"}, "view": {"query": "SELECT 1"}}"#
    )
    #expect(decoded.view?.useLegacySQL == true)
  }

  // Baseline: U.MaterializedViewDefinition.01
  @Test func materializedViewDefinitionRoundTrips() throws {
    let input = #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "mv"},
       "materializedView": {"query": "SELECT 1", "enableRefresh": true,
         "refreshIntervalMs": "1800000", "allowNonIncrementalDefinition": true}}
      """#
    let table = try Self.decode(
      #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "mv"},
       "materializedView": {"query": "SELECT 1", "enableRefresh": true,
         "refreshIntervalMs": "1800000", "allowNonIncrementalDefinition": true,
         "lastRefreshTime": "1600000000000"}}
      """#)
    var expected = MaterializedViewDefinition(
      query: "SELECT 1", enableRefresh: true, refreshInterval: .seconds(1800),
      allowNonIncrementalDefinition: true)
    expected.lastRefreshTime = Date(timeIntervalSince1970: 1_600_000_000)
    #expect(table.materializedView == expected)
    // `lastRefreshTime` is output only.
    #expect(try WireJSON.object(table.wire) == Self.wireObject(input))
    #expect(try (Self.body(table)["materializedView"] as? NSDictionary)?["lastRefreshTime"] == nil)
  }

  // Baseline: U.SnapshotTableDefinition.01
  @Test func snapshotDefinitionDecodesAndIsNotSent() throws {
    let table = try Self.decode(
      #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "s"}, "type": "SNAPSHOT",
       "snapshotDefinition": {"baseTableReference": {"projectId": "p", "datasetId": "d",
         "tableId": "base"}, "snapshotTime": "2024-01-02T03:04:05Z"}}
      """#)
    #expect(table.type == .snapshot)
    #expect(
      table.snapshotDefinition
        == SnapshotDefinition(
          baseTable: TableID(projectID: "p", datasetID: "d", tableID: "base"),
          snapshotTime: Date(timeIntervalSince1970: 1_704_164_645)))
    #expect(try WireJSON.object(table.wire)["snapshotDefinition"] == nil)
  }

  // Baseline: U.CloneDefinition.01
  @Test func cloneDefinitionDecodesAndIsNotSent() throws {
    let table = try Self.decode(
      #"""
      {"tableReference": {"projectId": "p", "datasetId": "d", "tableId": "c"},
       "cloneDefinition": {"baseTableReference": {"projectId": "p", "datasetId": "d",
         "tableId": "base"}, "cloneTime": "2024-01-02T03:04:05Z"}}
      """#)
    #expect(
      table.cloneDefinition
        == CloneDefinition(
          baseTable: TableID(projectID: "p", datasetID: "d", tableID: "base"),
          cloneTime: Date(timeIntervalSince1970: 1_704_164_645)))
    #expect(try WireJSON.object(table.wire)["cloneDefinition"] == nil)
  }

  // Baseline: U.TableConstraints.01, U.PrimaryKey.01, U.ForeignKey.01, U.ColumnReference.01
  @Test func tableConstraintsRoundTrip() throws {
    let table = try Self.decode(Self.inputJSON)
    let expected = TableConstraints(
      primaryKey: PrimaryKey(columns: ["n"]),
      foreignKeys: [
        ForeignKey(
          name: "fk", referencedTable: TableID(projectID: "p", datasetID: "d", tableID: "other"),
          columnReferences: [ColumnReference(referencingColumn: "n", referencedColumn: "id")])
      ])
    #expect(table.tableConstraints == expected)
    #expect(TableConstraints(wire: expected.wire) == expected)
  }

  // Baseline: U.TimePartitioning.01, U.TimePartitioning.02
  @Test(arguments: [
    TimePartitioning.PartitionType.day, .hour, .month, .year,
  ])
  fileprivate func timePartitioningRoundTrips(type: TimePartitioning.PartitionType) throws {
    var table = Table(id: TableID(projectID: "p", datasetID: "d", tableID: "t"))
    table.timePartitioning = TimePartitioning(type: type, expiration: .milliseconds(42))
    let object = try Self.body(table)
    let partitioning = try #require(object["timePartitioning"] as? NSDictionary)
    #expect(partitioning["type"] as? String == type.rawValue)
    #expect(partitioning["expirationMs"] as? String == "42")
    #expect(Table(wire: table.wire) == table)

    table.timePartitioning = TimePartitioning(type: type)
    #expect(Table(wire: table.wire).timePartitioning?.expiration == nil)
  }

  // Baseline: U.BigQueryImpl.22
  @Test func externalSchemaIsSentAsTableSchema() throws {
    var table = Table(id: TableID(projectID: "p", datasetID: "d", tableID: "ext"))
    var external = ExternalDataConfiguration(sourceURIs: ["gs://b/a.csv"], format: .csv)
    external.schema = Schema([Field("a", .string)])
    table.externalDataConfiguration = external
    let object = try Self.body(table)
    #expect(object["schema"] as? NSDictionary == (try WireJSON.object(external.schema!.wire)))
    let sent = try #require(object["externalDataConfiguration"] as? NSDictionary)
    #expect(sent["schema"] == nil)
    #expect(sent["sourceUris"] as? [String] == ["gs://b/a.csv"])
  }

  // Design: §7 (external schema)
  @Test func tableSchemaIsKeptWhenExternalConfigurationHasNone() throws {
    var table = Table(
      id: TableID(projectID: "p", datasetID: "d", tableID: "ext"),
      schema: Schema([Field("b", .int64)]))
    table.externalDataConfiguration = ExternalDataConfiguration(
      sourceURIs: ["gs://b/a.csv"], format: .csv)
    let object = try Self.body(table)
    #expect(object["schema"] as? NSDictionary == (try WireJSON.object(table.schema!.wire)))
  }

  // Design: §4 (Table.Field)
  @Test func clearableFieldsUseJSONPaths() throws {
    #expect(Table.Field.friendlyName.path == ["friendlyName"])
    #expect(Table.Field.partitionExpiration.path == ["timePartitioning", "expirationMs"])
    #expect(Table.Field.label("env").path == ["labels", "env"])
    #expect(Table.Field.primaryKey.path == ["tableConstraints", "primaryKey"])

    // A tag key of a domain-scoped project contains `.` and stays one JSON key.
    let table = Table(id: TableID(projectID: "p", datasetID: "d", tableID: "t"))
    let body =
      try JSONSerialization.jsonObject(
        with: try table.requestBody(clearing: [.resourceTag("example.com:p/env")])) as? NSDictionary
    let tags = try #require(body?["resourceTags"] as? NSDictionary)
    #expect(tags["example.com:p/env"] is NSNull)
  }
}
