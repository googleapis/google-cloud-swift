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

/// The state of an ongoing resumable transfer operation (such as an upload or download).
///
/// Passed to ``ResumePolicy`` methods to decide whether and how to resume after an error.
public struct ResumeState: Sendable, Equatable {
  /// The total number of bytes successfully transferred or committed so far.
  public var bytesTransferred: UInt64

  /// The total size of the object in bytes, if known.
  public var totalBytes: Int64?

  /// The number of consecutive errors encountered without making forward progress.
  ///
  /// This count is reset to 0 whenever forward progress (bytes transferred) is made.
  public var consecutiveErrorCount: UInt32

  /// The total number of resume attempts across the entire transfer operation.
  public var totalResumeCount: UInt32

  /// The time when the transfer operation originally started.
  public var start: ContinuousClock.Instant

  /// The time when forward progress was last made (or start time if no progress yet).
  public var lastProgressTime: ContinuousClock.Instant

  /// Creates a new `ResumeState` instance.
  ///
  /// - Parameters:
  ///   - bytesTransferred: Initial bytes transferred. Defaults to 0.
  ///   - totalBytes: Total object size in bytes if known. Defaults to `nil`.
  ///   - start: The clock instant when the operation started. Defaults to `.now`.
  public init(
    bytesTransferred: UInt64 = 0,
    totalBytes: Int64? = nil,
    start: ContinuousClock.Instant = .now
  ) {
    self.bytesTransferred = bytesTransferred
    self.totalBytes = totalBytes
    self.consecutiveErrorCount = 0
    self.totalResumeCount = 0
    self.start = start
    self.lastProgressTime = start
  }

  /// Override specific values using the `Then` idiom.
  ///
  /// ## Example
  /// ```
  /// let state = ResumeState().with { $0.bytesTransferred = 1024 }
  /// ```
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}
