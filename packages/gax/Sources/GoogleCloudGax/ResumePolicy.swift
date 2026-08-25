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

/// Determines how errors are handled and when to resume in long-running resumable operations.
///
/// Unlike a `RetryPolicy` which operates on a single atomic RPC attempt, a `ResumePolicy` controls
/// a series of API calls spanning an entire operation (e.g. uploads and downloads). It tracks forward
/// progress and handles recovery across transient network interruptions, failures, or dropped streams.
public protocol ResumePolicy<Details>: Sendable {
  /// The type of domain-specific details associated with this resume policy. Defaults to `Void`.
  associatedtype Details: Sendable = Void

  /// Queries the policy after an error during an operation.
  ///
  /// - Parameters:
  ///   - state: The current state of the operation.
  ///   - error: The last error encountered.
  /// - Returns: The resume decision (`.permanent`, `.exhausted`, or `.resume`).
  func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult

  /// Called when forward progress is made.
  ///
  /// - Parameter state: The current state of the operation to update.
  func onProgress(state: inout ResumeState<Details>)

  /// Returns the remaining duration for time-bounded resume policies.
  ///
  /// - Parameter state: The current state of the operation.
  /// - Returns: Remaining duration, or `nil` if the policy is not time-based.
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

extension RequestError {
  /// Indicates whether the error is transient and recoverable via session resumption.
  public var isRecoverableForResume: Bool {
    switch self {
    case .io:
      return true
    case .http(let details):
      let code = details.http_status_code
      // 408 (Request Timeout), 429 (Too Many Requests), 502 (Bad Gateway),
      // 503 (Service Unavailable), 504 (Gateway Timeout) are recoverable.
      return code == 408 || code == 429 || code == 502 || code == 503 || code == 504
    case .service(let details):
      let code = details.code
      return code == .unavailable || code == .resourceExhausted || code == .deadlineExceeded
    case .binding, .exhausted, .unimplemented, .malformedResponse:
      return false
    @unknown default:
      return false
    }
  }
}
