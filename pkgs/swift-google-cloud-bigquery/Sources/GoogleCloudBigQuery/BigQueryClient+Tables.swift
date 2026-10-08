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
public import GoogleGax

extension BigQueryClient {
  /// Creates a table, view, materialized view, or external table.
  ///
  /// `tables.insert` is not idempotent, so the request is not retried: a retry after a lost
  /// response would fail with HTTP 409.
  ///
  /// - Parameters:
  ///   - table: the table to create. A `nil` project in its ID means the client's project.
  ///   - selectedFields: the table fields to return. `tableReference` and `type` are always
  ///     returned. `nil` returns every field.
  ///   - options: per-call options.
  /// - Returns: the created table, as returned by the service.
  public func createTable(
    _ table: Table, selectedFields: [String]? = nil, options: RequestOptions = .init()
  ) async throws -> Table {
    let table = table.resolved(projectID: self.projectID)
    let request = HTTPRequest(
      method: .post, path: Self.tableCollectionPath(table.id.dataset),
      query: Self.tableFieldsQuery(selectedFields), body: try table.requestBody(),
      options: options)
    let created: GoogleCloudBigQueryV2.Table = try await self.transport.json(
      request, idempotent: false)
    return Table(wire: created)
  }

  /// Gets a table's metadata.
  ///
  /// - Parameters:
  ///   - id: the table. A `nil` project means the client's project.
  ///   - view: how much metadata to return. `nil` requests
  ///     ``TableMetadataView/storageStats``, as the Java client does.
  ///   - selectedFields: the table fields to return. `tableReference` and `type` are always
  ///     returned. `nil` returns every field.
  ///   - options: per-call options.
  /// - Returns: the table, or `nil` if it does not exist.
  public func getTable(
    _ id: TableID, view: TableMetadataView? = nil, selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Table? {
    let id = self.resolve(id)
    var query = Self.tableFieldsQuery(selectedFields)
    query.append(URLQueryItem(name: "view", value: (view ?? .storageStats).rawValue))
    let request = HTTPRequest(
      method: .get, path: Self.tableResourcePath(id), query: query, options: options)
    return try await self.transport.jsonOrNil(request, as: GoogleCloudBigQueryV2.Table.self)
      .map(Table.init(wire:))
  }

  /// Lists the tables in a dataset.
  ///
  /// The service returns partial tables; see ``Table`` for the fields that are set. Use
  /// ``getTable(_:view:selectedFields:options:)`` for the full metadata.
  ///
  /// - Parameters:
  ///   - dataset: the dataset. A `nil` project means the client's project.
  ///   - pageSize: the maximum number of tables per page.
  ///   - pageToken: a token from ``Page/nextPageToken`` to resume listing.
  ///   - options: per-call options.
  public func listTables(
    in dataset: DatasetID, pageSize: Int? = nil, pageToken: String? = nil,
    options: RequestOptions = .init()
  ) -> PagedSequence<Table> {
    let path = Self.tableCollectionPath(self.resolve(dataset))
    let transport = self.transport
    return PagedSequence { token in
      var query: [URLQueryItem] = []
      if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
      if let token = token ?? pageToken {
        query.append(URLQueryItem(name: "pageToken", value: token))
      }
      let list: GoogleCloudBigQueryV2.TableList = try await transport.json(
        HTTPRequest(method: .get, path: path, query: query, options: options), idempotent: true)
      return Page(items: list.tables.map(Table.init(listWire:)), nextPageToken: list.nextPageToken)
    }
  }

  /// Updates a table with PATCH semantics.
  ///
  /// Properties of `table` that are `nil` are left unchanged, and non-`nil` properties are set.
  /// To clear a property, list it in `clearing`. Output-only properties are ignored.
  ///
  /// The request is retried only when `ifMatch` is set, because a PATCH is not idempotent
  /// otherwise.
  ///
  /// - Parameters:
  ///   - table: the table ID and the properties to set.
  ///   - clearing: properties to clear, sent as JSON `null`.
  ///   - autodetectSchema: whether BigQuery should re-detect the schema of an external table.
  ///   - etag: when set, the update succeeds only if the table's ETag still matches (HTTP 412
  ///     otherwise).
  ///   - selectedFields: the table fields to return. `tableReference` and `type` are always
  ///     returned. `nil` returns every field.
  ///   - options: per-call options.
  /// - Returns: the updated table.
  public func updateTable(
    _ table: Table, clearing: Set<Table.Field> = [], autodetectSchema: Bool = false,
    ifMatch etag: String? = nil, selectedFields: [String]? = nil,
    options: RequestOptions = .init()
  ) async throws -> Table {
    let table = table.resolved(projectID: self.projectID)
    var query = Self.tableFieldsQuery(selectedFields)
    if autodetectSchema {
      query.append(URLQueryItem(name: "autodetect_schema", value: "true"))
    }
    var headers: [String: String] = [:]
    if let etag { headers["If-Match"] = etag }
    let request = HTTPRequest(
      method: .patch, path: Self.tableResourcePath(table.id), query: query, headers: headers,
      body: try table.requestBody(clearing: clearing), options: options)
    let updated: GoogleCloudBigQueryV2.Table = try await self.transport.json(
      request, idempotent: etag != nil)
    return Table(wire: updated)
  }

  /// Deletes a table.
  ///
  /// - Parameters:
  ///   - id: the table. A `nil` project means the client's project.
  ///   - options: per-call options.
  /// - Returns: `true` if the table was deleted, `false` if it did not exist. A retried
  ///   request whose first attempt deleted the table also returns `false`.
  @discardableResult
  public func deleteTable(_ id: TableID, options: RequestOptions = .init()) async throws -> Bool {
    let request = HTTPRequest(
      method: .delete, path: Self.tableResourcePath(self.resolve(id)), options: options)
    return try await self.transport.deleteOrFalse(request)
  }

  /// Returns the partition IDs of a partitioned table, such as `20240102` for a daily
  /// partition.
  ///
  /// Reads the `partition_id` column of the `{table}$__PARTITIONS_SUMMARY__` meta-table.
  ///
  /// - Parameters:
  ///   - table: the table. A `nil` project means the client's project.
  ///   - options: per-call options, used for every request.
  public func listPartitions(of table: TableID, options: RequestOptions = .init()) async throws
    -> [String]
  {
    var summary = table
    summary.tableID += "$__PARTITIONS_SUMMARY__"
    let rows = try await self.listRows(in: summary, options: options)
    guard let column = rows.schema.index(of: "partition_id") else { return [] }
    var partitions: [String] = []
    for try await row in rows {
      if case .scalar(let id) = row[column] { partitions.append(id) }
    }
    return partitions
  }
}

extension BigQueryClient {
  /// The fields that every table response includes (behavior doc §4 "Common rules").
  static let requiredTableFields = ["tableReference", "type"]

  /// `/bigquery/v2/projects/{p}/datasets/{d}/tables` for a resolved dataset.
  static func tableCollectionPath(_ dataset: DatasetID) -> String {
    "/bigquery/v2/projects/\(HTTPRequest.encode(segment: dataset.projectID ?? ""))"
      + "/datasets/\(HTTPRequest.encode(segment: dataset.datasetID))/tables"
  }

  /// `/bigquery/v2/projects/{p}/datasets/{d}/tables/{t}` for a resolved table.
  static func tableResourcePath(_ id: TableID) -> String {
    "\(Self.tableCollectionPath(id.dataset))/\(HTTPRequest.encode(segment: id.tableID))"
  }

  /// The `fields` query parameter for `selectedFields`, with the required table fields added.
  static func tableFieldsQuery(_ selectedFields: [String]?) -> [URLQueryItem] {
    guard let selectedFields else { return [] }
    var fields = Self.requiredTableFields
    fields.append(contentsOf: selectedFields.filter { !fields.contains($0) })
    return [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
  }
}

extension Table {
  /// Converts an item of `tables.list`, which carries only some of the table's fields.
  init(listWire wire: GoogleCloudBigQueryV2.ListFormatTable) {
    self.init(
      id: wire.tableReference.map(TableID.init(wire:)) ?? TableID(datasetID: "", tableID: ""),
      friendlyName: wire.friendlyName,
      labels: wire.labels.isEmpty ? nil : wire.labels)
    type = wire.type.nonEmpty.map(TableType.init(rawValue:))
    generatedID = wire.id.nonEmpty
    timePartitioning = wire.timePartitioning.map(TimePartitioning.init(wire:))
    rangePartitioning = wire.rangePartitioning.map(RangePartitioning.init(wire:))
    clustering = wire.clustering.map(Clustering.init(wire:))
    requirePartitionFilter = wire.requirePartitionFilter
    creationTime = Date(millisecondsSinceEpoch: wire.creationTime)
    expirationTime = Date(millisecondsSinceEpoch: wire.expirationTime)
  }
}
