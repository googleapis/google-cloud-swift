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

/// Aggregates performance counters across concurrent benchmark tasks.
///
/// An `actor` offers more than good enough performance in this case. We could have used
/// low-level atomics, but (a) the benchmark is heavily network I/O-bound, and (b) counter
/// increments occur only upon operation/batch completion. In these circumstances `actor`
/// dispatch overhead should be negligible.
public actor BenchmarkCounters {
  public private(set) var sampleCount: UInt64 = 0
  public private(set) var deleteCount: UInt64 = 0
  public private(set) var readCount: UInt64 = 0
  public private(set) var writeCount: UInt64 = 0
  public private(set) var deleteError: UInt64 = 0
  public private(set) var readError: UInt64 = 0
  public private(set) var writeError: UInt64 = 0

  public init() {}

  public func incrementSample() {
    sampleCount &+= 1
  }

  public func incrementDelete() {
    deleteCount &+= 1
  }

  public func incrementRead() {
    readCount &+= 1
  }

  public func incrementWrite() {
    writeCount &+= 1
  }

  public func incrementDeleteError() {
    deleteError &+= 1
  }

  public func incrementReadError() {
    readError &+= 1
  }

  public func incrementWriteError() {
    writeError &+= 1
  }

  public func snapshot() -> [(key: String, value: UInt64)] {
    [
      ("DELETE_COUNT", deleteCount),
      ("DELETE_ERROR", deleteError),
      ("READ_COUNT", readCount),
      ("READ_ERROR", readError),
      ("SAMPLE_COUNT", sampleCount),
      ("WRITE_COUNT", writeCount),
      ("WRITE_ERROR", writeError),
    ]
  }

  public func formattedDescription() -> String {
    let pairs = snapshot().map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ")
    return "Counters = [\(pairs)]"
  }

  public func errorDetails(error: (any Error)?) -> String {
    var details = snapshot().map { "\($0.key)=\($0.value)" }
    if let error = error {
      details.append("error=\(error)")
    }
    return details.joined(separator: ";").replacingOccurrences(of: ",", with: ";")
  }
}

public func logToStderr(_ message: String) {
  let line = message.hasSuffix("\n") ? message : message + "\n"
  if let data = line.data(using: .utf8) {
    FileHandle.standardError.write(data)
  }
}
