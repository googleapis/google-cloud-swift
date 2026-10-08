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
public import GoogleGax

extension BigQueryClient {
  /// Streams rows into a table (`tabledata.insertAll`).
  ///
  /// ```swift
  /// struct Person: Encodable { var name: String; var age: Int }
  /// let response = try await client.insertAll(
  ///   [try InsertRow(Person(name: "Ana", age: 31))],
  ///   into: TableID(datasetID: "people", tableID: "members"))
  /// for (index, errors) in response.rowErrors {
  ///   print("row \(index) failed: \(errors)")
  /// }
  /// ```
  ///
  /// By default every row without an ``InsertRow/insertID`` gets a random UUID, which BigQuery
  /// uses to drop duplicates, so the request is retried on transient errors. With
  /// ``InsertIDPolicy/none`` the request is retried only if every row has an insert ID.
  ///
  /// Per-row failures are returned in the response, not thrown.
  ///
  /// - Parameters:
  ///   - rows: the rows to insert.
  ///   - table: the destination table. A table without a project uses the client project.
  ///   - skipInvalidRows: insert the valid rows even if some rows are invalid. When `false`,
  ///     one invalid row fails the whole request.
  ///   - ignoreUnknownValues: accept rows with values for columns that are not in the schema,
  ///     dropping those values. When `false`, such rows are invalid.
  ///   - templateSuffix: if set, insert into the table named `table.tableID + templateSuffix`,
  ///     creating it with `table`'s schema if it does not exist.
  ///   - insertIDs: whether to generate insert IDs for rows that have none.
  ///   - options: per-request options.
  /// - Returns: the errors of the rows that failed.
  /// - Throws: ``BigQueryError`` if the request fails.
  public func insertAll(
    _ rows: [InsertRow],
    into table: TableID,
    skipInvalidRows: Bool = false,
    ignoreUnknownValues: Bool = false,
    templateSuffix: String? = nil,
    insertIDs: InsertIDPolicy = .generateMissing,
    options: RequestOptions = .init()
  ) async throws -> InsertAllResponse {
    let table = self.resolve(table)
    let wireRows = rows.map { row in
      InsertAllWireRequest.Row(
        insertId: row.insertID
          ?? (insertIDs == .generateMissing ? UUID().uuidString.lowercased() : nil),
        json: row.json)
    }
    let body = InsertAllWireRequest(
      rows: wireRows, skipInvalidRows: skipInvalidRows,
      ignoreUnknownValues: ignoreUnknownValues, templateSuffix: templateSuffix)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let path =
      "/bigquery/v2/projects/\(HTTPRequest.encode(segment: table.projectID ?? self.projectID))"
      + "/datasets/\(HTTPRequest.encode(segment: table.datasetID))"
      + "/tables/\(HTTPRequest.encode(segment: table.tableID))/insertAll"
    let request = HTTPRequest(
      method: .post, path: path, body: try encoder.encode(body), options: options)
    let response: InsertAllWireResponse = try await self.transport.json(
      request, idempotent: wireRows.allSatisfy { $0.insertId != nil })
    return InsertAllResponse(wire: response)
  }
}
