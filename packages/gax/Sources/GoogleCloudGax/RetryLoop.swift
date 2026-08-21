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

/// Runs a retry loop for a given function.
///
/// This struct calls an inner function as long as (1) the retry policy has not expired, (2) the
/// inner function has not returned a successful request, and (3) the retry throttler allows more
/// calls.
///
/// In between calls the function waits the amount of time prescribed by the backoff policy, using
/// `sleep` to implement any sleep.
@_spi(GoogleCloudInternal) public struct _RetryLoop: Sendable {
  let retryPolicy: any RetryPolicy
  let backoffPolicy: any BackoffPolicy
  let retryThrottler: any RetryThrottler
  let idempotent: Bool

  /// A simple constructor for tests.
  public init(
    retryPolicy: any RetryPolicy,
    backoffPolicy: any BackoffPolicy,
    retryThrottler: any RetryThrottler,
    idempotent: Bool
  ) {
    self.retryPolicy = retryPolicy
    self.backoffPolicy = backoffPolicy
    self.retryThrottler = retryThrottler
    self.idempotent = idempotent
  }

  /// Initializes a retry loop for the retry stub.
  ///
  /// The generated retry stub uses this initializer. It creates the retry loop based on the
  /// request and client options.
  public init(options: RequestOptions, withDefault: ClientOptions, idempotent: Bool) {
    self.retryPolicy = options.retryPolicy ?? withDefault.retryPolicy
    self.backoffPolicy = options.backoffPolicy ?? withDefault.backoffPolicy
    self.retryThrottler = options.retryThrottler ?? withDefault.retryThrottler
    self.idempotent = idempotent
  }

  /// Runs the retry loop.
  ///
  /// - Parameters:
  ///   - inner: the closure to retry. The closure consumes an optional `Duration` representing the
  ///     timeout for each attempt.
  /// - Returns: the value of the first successful attempt on `inner`.
  /// - Throws: the last error throws by `inner` if (a) the error is permanent (non-retryable), or
  ///   (b) the retry policy expired.
  public func run<Response>(
    attempt: (Duration?) async throws -> Response,
  ) async throws -> Response {
    try await run(inner: attempt, sleep: { (d: Duration) in try await Task.sleep(for: d) })
  }

  /// Runs the retry loop.
  ///
  /// - Parameters:
  ///   - inner: the closure to retry. The closure consumes an optional `Duration` representing the
  ///     timeout for each attempt.
  ///   - sleep: how to backoff. The closure sleeps for the prescribed duration.
  /// - Returns: the value of the first successful attempt on `inner`.
  /// - Throws: the last error throws by `inner` if (a) the error is permanent (non-retryable), or
  ///   (b) the retry policy expired.
  public func run<Response>(
    inner: (Duration?) async throws -> Response,
    sleep: (Duration) async throws -> Void
  ) async throws -> Response {
    let loopStart = ContinuousClock.now
    var attemptCount: UInt32 = 0
    var lastError: RequestError? = nil
    var nextDelay: Duration = .zero

    while true {
      var state = RetryState(idempotent: idempotent).with {
        $0.start = loopStart
        $0.attemptCount = attemptCount
      }
      let remainingTime = retryPolicy.remainingTime(state: state)

      if let prevError = lastError {
        if let remaining = remainingTime, remaining < nextDelay {
          // In Rust, this returns an "exhausted" error wrapping prevError.
          // Swift's RequestError doesn't have an exhausted case yet, so we
          // throw the last error seen.
          throw prevError
        }
        try await sleep(nextDelay)

        if retryThrottler.throttleRetryAttempt() {
          let throttleResult = retryPolicy.onThrottle(state: state, error: prevError)
          switch throttleResult {
          case .exhausted(let e):
            throw e
          case .retry(let e):
            lastError = e
            nextDelay = backoffPolicy.backoffDelayFor(state)
            continue
          }
        }
      }

      attemptCount += 1
      state.attemptCount = attemptCount

      do {
        let response = try await inner(remainingTime)
        retryThrottler.onSuccess()
        return response
      } catch {
        guard let requestError = error as? RequestError else {
          throw error
        }
        let flow = retryPolicy.onError(state: state, error: requestError)
        nextDelay = backoffPolicy.backoffDelayFor(state)
        retryThrottler.onRetryFailure(flow: flow)

        switch flow {
        case .permanent(let e), .exhausted(let e):
          throw e
        case .retry(let e):
          lastError = e
          continue
        }
      }
    }
  }
}
