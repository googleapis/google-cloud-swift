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
import GoogleCloudGax

/// Defines the strategy for resuming an interrupted multi-step or long-running operation
/// (such as resumable uploads and downloads).
public protocol ResumePolicy<Details>: Sendable {
  /// The domain-specific details type associated with the transfer state.
  associatedtype Details: Sendable = Void

  /// Evaluates an error and decides whether to resume or halt the transfer.
  ///
  /// - Parameters:
  ///   - state: The current `ResumeState`.
  ///   - error: The error encountered during the operation.
  /// - Returns: A `ResumeResult` indicating whether to resume, fail permanently, or exhaust attempts.
  func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult

  /// Updates policy state when forward progress is made.
  ///
  /// - Parameter state: The `ResumeState` to update.
  func onProgress(state: inout ResumeState<Details>)

  /// Returns the remaining time allowed by this policy, or `nil` if unbounded.
  ///
  /// - Parameter state: The current `ResumeState`.
  /// - Returns: The remaining duration, or `nil`.
  func remainingTime(state: ResumeState<Details>) -> Duration?
}

extension ResumePolicy {
  public func onProgress(state: inout ResumeState<Details>) {
    state.consecutiveErrorCount = 0
    state.lastProgressTime = .now
  }

  public func remainingTime(state: ResumeState<Details>) -> Duration? {
    nil
  }
}
