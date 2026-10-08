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

/// The rows of a table or query result, fetched lazily one page at a time.
///
/// ```swift
/// for try await row in result.rows {
///   print(row[0])
/// }
/// ```
public struct RowSequence: AsyncSequence, Sendable {
  public typealias Element = Row

  /// The schema of the rows. Empty if the result has no schema.
  public let schema: Schema

  /// The total number of rows, or `nil` if the service did not report it.
  ///
  /// A `nil` value does not mean the result is empty.
  public let totalRows: UInt64?

  let rows: PagedSequence<Row>

  /// Creates a sequence over pages of rows.
  public init(schema: Schema, totalRows: UInt64?, rows: PagedSequence<Row>) {
    self.schema = schema
    self.totalRows = totalRows
    self.rows = rows
  }

  /// Creates a sequence over a fixed list of rows, for example in tests.
  public init(schema: Schema, rows: [Row]) {
    self.init(schema: schema, totalRows: UInt64(rows.count), rows: PagedSequence(rows))
  }

  /// The pages of rows, with their page tokens.
  public var pages: PagedSequence<Row>.Pages { self.rows.pages }

  /// Fetches every remaining page and returns all the rows.
  public func collect() async throws -> [Row] {
    try await self.rows.collect()
  }

  public func makeAsyncIterator() -> PagedSequence<Row>.AsyncIterator {
    self.rows.makeAsyncIterator()
  }
}
