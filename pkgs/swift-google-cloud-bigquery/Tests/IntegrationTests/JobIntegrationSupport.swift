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
import Testing

@testable import GoogleCloudBigQuery

/// Helpers shared by the job, query, load, and upload integration tests.
enum JobsIT {
  /// The slice name used in resource names.
  static let slice = "jobs"

  /// The fully qualified, back-quoted SQL name of `table`.
  static func sql(_ table: TableID) -> String {
    "`\(table.projectID!).\(table.datasetID).\(table.tableID)`"
  }

  /// A unique table ID in `dataset`.
  static func table(_ dataset: DatasetID, _ name: String = "t") -> TableID {
    TableID(dataset: dataset, tableID: "\(name)_\(IntegrationTest.randomHex())")
  }

  /// A unique job ID, so leaked jobs are attributable to these tests.
  static func jobID(location: String? = nil) -> JobID {
    JobID(jobID: "\(IntegrationTest.uniqueName(Self.slice))", location: location)
  }

  /// Creates `table` with three rows: `(name STRING, n INT64)` = `("a", 1)`, `("b", 2)`,
  /// `("c", 3)`.
  @discardableResult
  static func createSampleTable(
    _ client: BigQueryClient, _ table: TableID, location: String? = nil
  ) async throws -> TableID {
    _ = try await client.query(
      QueryJobConfiguration(
        """
        CREATE TABLE \(Self.sql(table)) AS
        SELECT * FROM UNNEST([STRUCT('a' AS name, 1 AS n), ('b', 2), ('c', 3)])
        """), location: location)
    return table
  }

  /// The values of `column` in `rows`, as BigQuery strings (`nil` for NULL).
  static func scalars(_ rows: [Row], _ column: String) -> [String?] {
    rows.map { row in
      if case .scalar(let value) = row[column] { return value }
      return nil
    }
  }

  /// Runs `sql` and returns the values of `column` in every row.
  static func column(_ client: BigQueryClient, _ sql: String, _ column: String) async throws
    -> [String?]
  {
    Self.scalars(try await client.query(sql).rows.collect(), column)
  }
}
