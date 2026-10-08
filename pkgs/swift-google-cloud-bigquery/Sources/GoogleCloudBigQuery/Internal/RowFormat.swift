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

/// The wire format options sent on every row-reading request (`jobs.query`, `getQueryResults`,
/// and `tabledata.list`).
///
/// `ISO8601_STRING` preserves picoseconds on `TIMESTAMP(12)` columns (whereas
/// `useInt64Timestamp` truncates them to microseconds) and cannot be combined with
/// `useInt64Timestamp` on the wire.
enum RowFormat {
  /// The `formatOptions` query item for `getQueryResults` and `tabledata.list`.
  static let queryItem = URLQueryItem(
    name: "formatOptions.timestampOutputFormat", value: "ISO8601_STRING")

  /// The `formatOptions` field for `jobs.query`.
  static let formatOptions = GoogleCloudBigQueryV2.DataFormatOptions().with {
    $0.timestampOutputFormat = .iso8601String
  }
}
