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
import GoogleWKT

/// The result of ``BigQueryClient/insertAll(_:into:skipInvalidRows:ignoreUnknownValues:templateSuffix:insertIDs:options:)``.
///
/// Rows that are not listed in ``rowErrors`` were inserted, unless the request set neither
/// `skipInvalidRows` nor `ignoreUnknownValues` and another row failed: then BigQuery inserts no
/// rows, and the rows without errors of their own carry a `stopped` error.
public struct InsertAllResponse: Sendable, Equatable {
  /// The errors of each failed row, keyed by the row's index in the request.
  public var rowErrors: [Int: [BigQueryError.Detail]]

  /// Creates a response.
  public init(rowErrors: [Int: [BigQueryError.Detail]] = [:]) {
    self.rowErrors = rowErrors
  }

  /// `true` if any row failed.
  public var hasErrors: Bool { !self.rowErrors.isEmpty }
}

/// The body of a `tabledata.insertAll` request. The method is not in the generated protos.
struct InsertAllWireRequest: Encodable {
  struct Row: Encodable {
    var insertId: String?
    var json: WKTStruct
  }

  var rows: [Row]
  var skipInvalidRows: Bool
  var ignoreUnknownValues: Bool
  var templateSuffix: String?
}

/// The body of a `tabledata.insertAll` response.
struct InsertAllWireResponse: Decodable {
  struct InsertError: Decodable {
    var index: Int?
    var errors: [GoogleCloudBigQueryV2.ErrorProto]?
  }

  var insertErrors: [InsertError]?
}

extension InsertAllResponse {
  init(wire: InsertAllWireResponse) {
    var rowErrors: [Int: [BigQueryError.Detail]] = [:]
    for error in wire.insertErrors ?? [] {
      rowErrors[error.index ?? 0, default: []].append(
        contentsOf: (error.errors ?? []).map(BigQueryError.Detail.init(wire:)))
    }
    self.init(rowErrors: rowErrors)
  }
}
