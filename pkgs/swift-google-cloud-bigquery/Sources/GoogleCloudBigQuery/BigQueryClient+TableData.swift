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
  /// Reads the rows of a table.
  ///
  /// The first page is fetched before this method returns, so ``RowSequence/totalRows`` is
  /// available at once. Later pages are fetched lazily as the sequence is iterated, with the
  /// same `pageSize` and `selectedFields`.
  ///
  /// ```swift
  /// let rows = try await client.listRows(in: TableID(datasetID: "d", tableID: "t"))
  /// for try await row in rows {
  ///   print(row["name"] ?? .null)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - table: the table. A `nil` project means the client's project.
  ///   - schema: the table's schema. When `nil`, the client first reads it with one
  ///     `tables.get` request, so rows can always be accessed by name. Pass it to skip that
  ///     request. With `selectedFields`, the rows use only the selected fields of the schema.
  ///   - selectedFields: the columns to return, for example `["a", "e.d.f"]`. `nil` returns
  ///     every column.
  ///   - startIndex: the zero-based index of the first row to return.
  ///   - pageSize: the maximum number of rows per page.
  ///   - pageToken: a token from ``Page/nextPageToken`` to resume reading.
  ///   - options: per-call options, used for every request.
  /// - Throws: ``BigQueryError`` if the table does not exist or a request fails.
  public func listRows(
    in table: TableID, schema: Schema? = nil, selectedFields: [String]? = nil,
    startIndex: UInt64? = nil, pageSize: Int? = nil, pageToken: String? = nil,
    options: RequestOptions = .init()
  ) async throws -> RowSequence {
    let id = self.resolve(table)
    let rowSchema: Schema
    if let schema {
      rowSchema = selectedFields.map { schema.selecting($0) } ?? schema
    } else {
      // The service projects the schema to `selectedFields` the same way as the rows.
      rowSchema = try await self.tableSchema(id, selectedFields: selectedFields, options: options)
    }
    let transport = self.transport
    let path = Self.tableResourcePath(id) + "/data"
    let fetch = { @Sendable (token: String?, startIndex: UInt64?) async throws -> TableDataList in
      var query = [RowFormat.queryItem]
      if let pageSize { query.append(URLQueryItem(name: "maxResults", value: String(pageSize))) }
      if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
      if let startIndex {
        query.append(URLQueryItem(name: "startIndex", value: String(startIndex)))
      }
      if let selectedFields {
        query.append(
          URLQueryItem(name: "selectedFields", value: selectedFields.joined(separator: ",")))
      }
      return try await transport.json(
        HTTPRequest(method: .get, path: path, query: query, options: options), idempotent: true)
    }
    let first = try await fetch(pageToken, startIndex)
    let rows = PagedSequence(firstPage: try first.page(schema: rowSchema)) { token in
      // The page token carries the position, so later pages do not resend `startIndex`
      // (Java resets it to 0; U.BigQueryImpl.31).
      try await fetch(token, nil).page(schema: rowSchema)
    }
    return RowSequence(
      schema: rowSchema, totalRows: first.totalRows.flatMap(UInt64.init), rows: rows)
  }

  /// Reads the schema of `id`, restricted to `selectedFields` when set.
  private func tableSchema(
    _ id: TableID, selectedFields: [String]?, options: RequestOptions
  ) async throws -> Schema {
    var query = [
      URLQueryItem(name: "fields", value: "schema"),
      URLQueryItem(name: "view", value: TableMetadataView.basic.rawValue),
    ]
    if let selectedFields {
      query.append(
        URLQueryItem(name: "selectedFields", value: selectedFields.joined(separator: ",")))
    }
    let table: GoogleCloudBigQueryV2.Table = try await self.transport.json(
      HTTPRequest(method: .get, path: Self.tableResourcePath(id), query: query, options: options),
      idempotent: true)
    return table.schema.map(Schema.init(wire:)) ?? Schema([])
  }
}

/// The response of `tabledata.list`, which the generated protos do not define (design §13).
struct TableDataList: Decodable, Sendable {
  /// The total number of rows in the table, as a decimal string.
  var totalRows: String?
  /// The token of the next page; absent or empty on the last page.
  var pageToken: String?
  /// The rows in the `{"f": [{"v": ...}]}` format.
  var rows: [WireRow]?

  func page(schema: Schema) throws -> Page<Row> {
    Page(
      items: try Row.rows(from: self.rows ?? [], schema: schema),
      nextPageToken: self.pageToken?.nonEmpty)
  }
}

extension Schema {
  /// The fields that `tabledata.list` returns for `selectedFields`: the selected fields, and
  /// for nested paths such as `e.d.f` only the selected subfields, in schema order.
  fileprivate func selecting(_ selectedFields: [String]) -> Schema {
    let paths = selectedFields.map { $0.lowercased().split(separator: ".").map(String.init) }
    return Schema(Self.select(self.fields, paths: paths))
  }

  private static func select(_ fields: [Field], paths: [[String]]) -> [Field] {
    fields.compactMap { field in
      let matching = paths.filter { $0.first == field.name.lowercased() }
      if matching.isEmpty { return nil }
      if field.fields.isEmpty || matching.contains(where: { $0.count == 1 }) { return field }
      var selected = field
      selected.fields = Self.select(field.fields, paths: matching.map { Array($0.dropFirst()) })
      return selected
    }
  }
}
