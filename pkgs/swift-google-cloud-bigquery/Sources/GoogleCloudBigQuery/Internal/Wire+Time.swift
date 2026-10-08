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
import GoogleWKT

// Conversions for the two time representations in the BigQuery v2 API: int64 milliseconds since
// the epoch (`creationTime`, `lastModifiedTime`, `expirationTime`, job statistics) and
// `google.protobuf.Timestamp` (`snapshotTime`, ...).

extension Date {
  /// Converts milliseconds since the epoch. Returns `nil` for `0`, the proto3 value of an unset
  /// field.
  init?(millisecondsSinceEpoch milliseconds: Int64) {
    guard milliseconds != 0 else { return nil }
    self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
  }

  /// Milliseconds since the epoch, rounded to the nearest millisecond.
  var millisecondsSinceEpoch: Int64 {
    Int64((self.timeIntervalSince1970 * 1000).rounded())
  }

  /// Converts a protobuf timestamp.
  init(wire: WKTTimestamp) {
    self.init(timeIntervalSince1970: Double(wire.seconds) + Double(wire.nanos) / 1_000_000_000)
  }
}

extension WKTTimestamp {
  /// Converts a date, truncated to whole microseconds (BigQuery's precision).
  ///
  /// - Throws: `WKTTimestampError.outOfRange` for dates outside years 1 through 9999.
  init(date: Date) throws {
    let micros = (date.timeIntervalSince1970 * 1_000_000).rounded(.down)
    let seconds = (micros / 1_000_000).rounded(.down)
    let nanos = Int32((micros - seconds * 1_000_000) * 1000)
    try self.init(seconds: Int64(seconds), nanos: nanos)
  }
}
