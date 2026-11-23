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

package import GoogleGax

package enum PubSubRetryExecutor {
  package static func execute<T: Sendable>(
    retryPolicy: any GoogleGax.RetryPolicy,
    backoffPolicy: any GoogleGax.BackoffPolicy,
    throttler: any GoogleGax.RetryThrottler,
    clock: any PubSubClock,
    operation: @Sendable (_ remainingTime: Duration?) async throws -> T
  ) async throws -> T {
    let clockStart = clock.now
    var attemptCount = 0
    var lastError: GoogleGax.RequestError?

    func makeState(attemptCount: Int) -> RetryState {
      let elapsed = clock.now - clockStart
      return RetryState(start: ContinuousClock.now - elapsed, attemptCount: attemptCount)
    }

    while true {
      try Task.checkCancellation()
      attemptCount += 1

      let currentState = makeState(attemptCount: attemptCount)
      let currentRemaining = retryPolicy.remainingTime(state: currentState)
      if attemptCount > 1, let currentRemaining, currentRemaining <= .zero, let lastError {
        throw lastError
      }

      if attemptCount > 1 && throttler.throttleRetryAttempt(), let previousError = lastError {
        switch retryPolicy.onThrottle(state: currentState, error: previousError) {
        case .exhausted(let exhaustedError):
          throw exhaustedError
        case .retry(let throttledError):
          let delay = backoffPolicy.backoffDelay(for: currentState)
          if let remaining = retryPolicy.remainingTime(state: currentState),
            remaining <= .zero || delay >= remaining
          {
            throw throttledError
          }
          try await clock.sleep(for: delay)
          lastError = throttledError
          continue
        @unknown default:
          throw previousError
        }
      }

      do {
        let result = try await operation(currentRemaining)
        throttler.onSuccess()
        return result
      } catch is CancellationError {
        throw CancellationError()
      } catch let pubSubError as PubSubError {
        throw pubSubError
      } catch {
        let requestError = (error as? GoogleGax.RequestError) ?? .io(error)
        let state = makeState(attemptCount: attemptCount)
        switch retryPolicy.onError(state: state, error: requestError) {
        case .permanent(let permanentError):
          throw permanentError
        case .exhausted(let exhaustedError):
          throttler.onRetryFailure(.exhausted(exhaustedError))
          throw exhaustedError
        case .retry(let retryableError):
          let delay = backoffPolicy.backoffDelay(for: state)
          if let remaining = retryPolicy.remainingTime(state: state),
            remaining <= .zero || delay >= remaining
          {
            throttler.onRetryFailure(.exhausted(retryableError))
            throw retryableError
          }
          throttler.onRetryFailure(.retry(retryableError))
          try await clock.sleep(for: delay)
          lastError = retryableError
        @unknown default:
          throw requestError
        }
      }
    }
  }
}
