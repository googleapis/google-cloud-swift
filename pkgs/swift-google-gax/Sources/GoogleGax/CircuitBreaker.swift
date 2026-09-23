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
import Synchronization

/// A `CircuitBreaker` throttler rejects retry attempts if the success rate is too low.
///
/// This class implements the [gRPC throttler] algorithm. The throttler works by tracking the number
/// of available "tokens" for a retry attempt. If this number goes below a threshold **all** retry
/// attempts are throttled.
///
/// Retry failures decrement the number of tokens by a given cost. Completed requests (successfully
/// or not) increase the tokens by `1`.
///
/// Note: the number of tokens may go below the throttling threshold as multiple concurrent requests
/// may fail and decrease the token count.
///
/// Note: throttling only applies to retry attempts, the initial requests is never throttled. This
/// may increases the token count even if all retry attempts are throttled.
///
/// [gRPC throttler]: https://github.com/grpc/proposal/blob/master/A6-client-retries.md
public final class CircuitBreaker: RetryThrottler, Sendable {
  private struct State {
    var curTokens: Int

    mutating func onSuccess(_ maxTokens: Int) {
      self.curTokens = min(maxTokens, self.curTokens.addingReportingOverflow(1).partialValue)
    }
  }

  private let maxTokens: Int
  private let minTokens: Int
  private let errorCost: Int
  private let state: Mutex<State>

  /// Creates a new instance with the default configuration.
  ///
  /// The default uses 100 initial tokens, each error costs 10 tokens, and the circuit breaker is
  /// triggered if the number of tokens goes below 50.
  public init() {
    self.maxTokens = 100
    self.minTokens = 50
    self.errorCost = 10
    self.state = Mutex(State(curTokens: 100))
  }

  /// Creates a new instance.
  ///
  /// - Parameters:
  ///   - tokens: The initial number of tokens.
  ///   - minTokens: Stops accepting retry attempts when the number of tokens is at or below this value.
  ///   - errorCost: Decrease the token count by this value on failed request attempts.
  /// - Throws:
  ///   - ``RetryThrottlerError/tokensOutOfRange(tokens:minTokens:errorCost:)`` if any parameter is negative.
  ///   - ``RetryThrottlerError/tooFewMinTokens(min:initial:)`` if `minTokens` > `tokens`.
  public init(tokens: Int, minTokens: Int, errorCost: Int) throws {
    if tokens < 0 || minTokens < 0 || errorCost < 0 {
      throw RetryThrottlerError.tokensOutOfRange(
        tokens: tokens, minTokens: minTokens, errorCost: errorCost)
    }
    if minTokens > tokens {
      throw RetryThrottlerError.tooFewMinTokens(min: minTokens, initial: tokens)
    }
    self.maxTokens = tokens
    self.minTokens = minTokens
    self.errorCost = errorCost
    self.state = Mutex(State(curTokens: tokens))
  }

  /// Creates a new instance, adjusting `tokens`, `minTokens`, and `errorCost` to valid non-negative ranges if needed.
  ///
  /// - Parameters:
  ///   - tokens: The initial number of tokens. Clamped to be non-negative (`max(0, tokens)`).
  ///   - minTokens: Stops accepting retry attempts when the number of tokens is at or below this
  ///     value. Clamped to be in the `[0, tokens]` range.
  ///   - errorCost: Decrease the token count by this value on failed request attempts. Clamped to be
  ///     non-negative (`max(0, errorCost)`).
  public init(clampingTokens tokens: Int, minTokens: Int, errorCost: Int) {
    let clampedTokens = max(0, tokens)
    self.maxTokens = clampedTokens
    self.minTokens = min(max(0, minTokens), clampedTokens)
    self.errorCost = max(0, errorCost)
    self.state = Mutex(State(curTokens: clampedTokens))
  }

  public func throttleRetryAttempt() -> Bool {
    return state.withLock { $0.curTokens <= minTokens }
  }

  public func onRetryFailure(flow: RetryResult) {
    state.withLock { state in
      switch flow {
      case .retry, .exhausted:
        if state.curTokens >= errorCost {
          state.curTokens -= errorCost
        } else {
          state.curTokens = 0
        }
      case .permanent:
        // A permanent error is treated as a success for throttling purposes. It indicates
        // the request was received by the service.
        state.onSuccess(self.maxTokens)
      }
    }
  }

  public func onSuccess() {
    state.withLock { state in
      state.onSuccess(self.maxTokens)
    }
  }
}
