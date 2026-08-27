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

/// Runs a resume loop for long-running or multi-step operations (such as resumable uploads and downloads).
///
/// Unlike `_RetryLoop` which manages atomic single-RPC retries with `RetryPolicy`, `_ResumeLoop`
/// tracks forward progress and handles transient error recovery, session resumption,
/// and backoff across an entire operation using a `ResumePolicy` and `BackoffPolicy`.
package struct _ResumeLoop<Details: Sendable>: Sendable {
  package let resumePolicy: any ResumePolicy<Details>
  package let backoffPolicy: any BackoffPolicy

  /// Creates a new `_ResumeLoop` with the specified resume and backoff policies.
  package init(
    resumePolicy: any ResumePolicy<Details>,
    backoffPolicy: any BackoffPolicy
  ) {
    self.resumePolicy = resumePolicy
    self.backoffPolicy = backoffPolicy
  }

  /// Updates forward progress, resetting consecutive errors and updating the last progress timestamp.
  ///
  /// - Parameter state: The `ResumeState` to update.
  package func onProgress(state: inout ResumeState<Details>) {
    resumePolicy.onProgress(state: &state)
  }

  /// Handles an error encountered during a step of a resumable operation.
  ///
  /// Increments consecutive error and total resume counters in `state`, consults `resumePolicy`,
  /// and sleeps for the duration prescribed by `backoffPolicy` if the error is recoverable.
  ///
  /// - Parameters:
  ///   - state: The `ResumeState` to update.
  ///   - error: The error encountered.
  ///   - sleep: The sleep closure used to apply backoff delay. Defaults to `Task.sleep(for:)`.
  /// - Throws: The error if non-recoverable, or if the policy limits are exhausted.
  package func handleError(
    state: inout ResumeState<Details>,
    error: any Error,
    sleep: (Duration) async throws -> Void = { (d: Duration) in try await Task.sleep(for: d) }
  ) async throws {
    guard let requestError = error as? RequestError else {
      throw error
    }
    state.consecutiveErrorCount += 1
    state.totalResumeCount += 1

    let remainingTime = resumePolicy.remainingTime(state: state)
    let decision = resumePolicy.onError(state: state, error: requestError)

    switch decision {
    case .permanent(let e), .exhausted(let e):
      throw e
    case .resume(let e):
      let retryState = RetryState().with {
        $0.attemptCount = state.consecutiveErrorCount
      }
      let delay = backoffPolicy.backoffDelayFor(retryState)
      if let remaining = remainingTime, remaining < delay {
        throw e
      }
      if delay > .zero {
        try await sleep(delay)
      }
    }
  }

  /// Runs an async attempt closure, retrying on recoverable errors according to the resume policy and backoff policy.
  ///
  /// - Parameters:
  ///   - state: The `ResumeState` updated across attempts.
  ///   - attempt: The closure to execute. It receives the remaining duration (if time-bounded).
  /// - Returns: The value returned by the successful attempt.
  /// - Throws: The error if non-recoverable or if the resume policy is exhausted.
  package func run<Response>(
    state: inout ResumeState<Details>,
    attempt: (_ remainingTime: Duration?) async throws -> Response
  ) async throws -> Response {
    try await run(
      state: &state, attempt: attempt,
      sleep: { (d: Duration) in try await Task.sleep(for: d) })
  }

  /// Runs an async attempt closure with a custom sleep function.
  package func run<Response>(
    state: inout ResumeState<Details>,
    attempt: (_ remainingTime: Duration?) async throws -> Response,
    sleep: (Duration) async throws -> Void
  ) async throws -> Response {
    while true {
      let remainingTime = resumePolicy.remainingTime(state: state)
      do {
        let response = try await attempt(remainingTime)
        return response
      } catch {
        try await handleError(state: &state, error: error, sleep: sleep)
      }
    }
  }

  /// Runs an async attempt closure with a value-passed `ResumeState`.
  package func run<Response>(
    state: ResumeState<Details>,
    attempt: (_ remainingTime: Duration?) async throws -> Response
  ) async throws -> Response {
    var state = state
    return try await run(state: &state, attempt: attempt)
  }

  /// Runs an async attempt closure with a value-passed `ResumeState` and custom sleep function.
  package func run<Response>(
    state: ResumeState<Details>,
    attempt: (_ remainingTime: Duration?) async throws -> Response,
    sleep: (Duration) async throws -> Void
  ) async throws -> Response {
    var state = state
    return try await run(state: &state, attempt: attempt, sleep: sleep)
  }
}

extension _ResumeLoop where Details == Void {
  /// Runs an async attempt closure starting with a fresh default `ResumeState`.
  package func run<Response>(
    attempt: (_ remainingTime: Duration?) async throws -> Response
  ) async throws -> Response {
    var state = ResumeState()
    return try await run(state: &state, attempt: attempt)
  }

  /// Runs an async attempt closure starting with a fresh default `ResumeState` and custom sleep function.
  package func run<Response>(
    attempt: (_ remainingTime: Duration?) async throws -> Response,
    sleep: (Duration) async throws -> Void
  ) async throws -> Response {
    var state = ResumeState()
    return try await run(state: &state, attempt: attempt, sleep: sleep)
  }
}
