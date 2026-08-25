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

/// The input into a resume policy query, tracking progress and error state of an ongoing resumable operation.
///
/// On an error or forward progress event, the client library updates and provides an instance of this
/// struct to the ``ResumePolicy``. Specific domains or operations (such as storage uploads and downloads)
/// provide domain-specific metadata via the `Details` generic parameter.
public struct ResumeState<Details: Sendable>: Sendable {
  /// The number of consecutive errors encountered without making forward progress.
  ///
  /// This count is reset to 0 whenever forward progress is made.
  public var consecutiveErrorCount: UInt32

  /// The total number of resume attempts across the entire operation.
  public var totalResumeCount: UInt32

  /// The time when the operation originally started.
  public var start: ContinuousClock.Instant

  /// The time when forward progress was last made (or start time if no progress yet).
  public var lastProgressTime: ContinuousClock.Instant

  /// Domain-specific progress and context details.
  public var details: Details

  /// Creates a new `ResumeState` instance with domain-specific details.
  ///
  /// - Parameters:
  ///   - details: Domain-specific progress details.
  ///   - start: The clock instant when the operation started. Defaults to `.now`.
  public init(
    details: Details,
    start: ContinuousClock.Instant = .now
  ) {
    self.consecutiveErrorCount = 0
    self.totalResumeCount = 0
    self.start = start
    self.lastProgressTime = start
    self.details = details
  }

  /// Override specific values using the `Then` idiom.
  ///
  /// ## Example
  /// ```
  /// let state = ResumeState(details: ()).with { $0.consecutiveErrorCount = 2 }
  /// ```
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

extension ResumeState where Details == Void {
  /// Creates a new `ResumeState` instance with `Void` details.
  ///
  /// - Parameter start: The clock instant when the operation started. Defaults to `.now`.
  public init(start: ContinuousClock.Instant = .now) {
    self.init(details: (), start: start)
  }
}

extension ResumeState: Equatable where Details: Equatable {}
