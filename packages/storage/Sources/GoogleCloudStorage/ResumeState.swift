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

/// State tracked across attempts during a resumable transfer operation.
public struct ResumeState<Details: Sendable>: Sendable {
  /// The consecutive number of errors encountered without making forward progress.
  public var consecutiveErrorCount: UInt32

  /// The total number of resume attempts made across the entire operation.
  public var totalResumeCount: UInt32

  /// The timestamp when the transfer operation began.
  public var start: ContinuousClock.Instant

  /// The timestamp when forward progress was last recorded.
  public var lastProgressTime: ContinuousClock.Instant

  /// Additional domain-specific details (e.g. byte offset, total bytes).
  public var details: Details

  /// Creates a new `ResumeState` instance.
  public init(
    details: Details,
    consecutiveErrorCount: UInt32 = 0,
    totalResumeCount: UInt32 = 0,
    start: ContinuousClock.Instant = .now,
    lastProgressTime: ContinuousClock.Instant? = nil
  ) {
    self.details = details
    self.consecutiveErrorCount = consecutiveErrorCount
    self.totalResumeCount = totalResumeCount
    self.start = start
    self.lastProgressTime = lastProgressTime ?? start
  }

  /// Mutates `self` using a builder closure and returns the modified state.
  public func with(_ mutate: (inout Self) -> Void) -> Self {
    var copy = self
    mutate(&copy)
    return copy
  }
}

extension ResumeState where Details == Void {
  /// Creates a new `ResumeState` with default `Void` details.
  public init(
    consecutiveErrorCount: UInt32 = 0,
    totalResumeCount: UInt32 = 0,
    start: ContinuousClock.Instant = .now,
    lastProgressTime: ContinuousClock.Instant? = nil
  ) {
    self.init(
      details: (),
      consecutiveErrorCount: consecutiveErrorCount,
      totalResumeCount: totalResumeCount,
      start: start,
      lastProgressTime: lastProgressTime
    )
  }
}

extension ResumeState: Equatable where Details: Equatable {}
