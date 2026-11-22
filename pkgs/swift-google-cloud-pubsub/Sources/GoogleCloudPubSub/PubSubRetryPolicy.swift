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
public import GoogleGax
public import GoogleRpc

/// A retry policy tailored for Google Cloud Pub/Sub data-plane RPCs.
///
/// By default, `PubSubRetryPolicy` retries transient gRPC status codes
/// (`DEADLINE_EXCEEDED`, `RESOURCE_EXHAUSTED`, `ABORTED`, `INTERNAL`, and `UNAVAILABLE`)
/// as well as transport I/O failures, up to a 600-second total elapsed time limit.
///
/// Callers may customize ``retryableCodes``, ``timeLimit``, or ``maxAttempts``, or
/// pass any custom `GoogleGax.RetryPolicy` via `GoogleGax.RequestOptions/retryPolicy`.
///
/// ```swift
/// let options = TopicPublisherOptions().with {
///   $0.request.retryPolicy = PubSubRetryPolicy().with {
///     $0.timeLimit = .seconds(30)
///     $0.maxAttempts = 5
///   }
/// }
/// ```
public struct PubSubRetryPolicy: GoogleGax.RetryPolicy, Sendable, Equatable {
  /// The canonical set of transient gRPC status codes retried by Pub/Sub clients.
  public static let defaultRetryableCodes: Set<GoogleRpc.Code> = [
    .deadlineExceeded,
    .resourceExhausted,
    .aborted,
    .internal,
    .unavailable,
  ]

  /// The default retry policy used by `Publisher` and `BlockingPublisherClient` (600s time limit).
  public static var defaultPublishPolicy: Self {
    Self()
  }

  /// The default retry backoff policy (`100ms` initial delay, `60s` maximum delay, `1.3` scaling factor).
  public static var defaultBackoffPolicy: ExponentialBackoff {
    ExponentialBackoff(clamping: .milliseconds(100), maximumDelay: .seconds(60), scaling: 1.3)
  }

  /// gRPC status codes eligible for retry.
  public var retryableCodes: Set<GoogleRpc.Code> = Self.defaultRetryableCodes

  /// Whether transport-level I/O failures (`RequestError.io`) are eligible for retry.
  public var retryOnIO: Bool = true

  /// Optional maximum wall-clock elapsed time limit for the entire retry loop.
  ///
  /// Defaults to `.seconds(600)`. Set to `nil` to disable the time bound.
  public var timeLimit: Duration? = .seconds(600)

  /// Optional maximum number of RPC attempts (including the initial attempt).
  ///
  /// Defaults to `nil` (unbounded attempts within ``timeLimit``).
  public var maxAttempts: Int? = nil

  /// Creates a `PubSubRetryPolicy` with the standard Pub/Sub retry defaults.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }

  /// Evaluates whether a failed RPC `error` should be retried given `state`.
  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    guard self.isTransient(error) else {
      return .permanent(error)
    }
    if let maxAttempts, state.attemptCount >= maxAttempts {
      return .exhausted(error)
    }
    if let timeLimit, ContinuousClock.now >= state.start + timeLimit {
      return .exhausted(error)
    }
    return .retry(error)
  }

  /// Evaluates retry eligibility when client-side retry throttling rejects an attempt.
  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    if let maxAttempts, state.attemptCount >= maxAttempts {
      return .exhausted(
        .exhausted(.attemptCount(maximumAttempts: maxAttempts, underlyingError: error)))
    }
    if let timeLimit, ContinuousClock.now >= state.start + timeLimit {
      return .exhausted(
        .exhausted(.elapsedTime(maximumDuration: timeLimit, underlyingError: error)))
    }
    return .retry(error)
  }

  /// Returns the remaining wall-clock budget for the retry loop, or `nil` when ``timeLimit`` is `nil`.
  public func remainingTime(state: RetryState) -> Duration? {
    guard let timeLimit else {
      return nil
    }
    let deadline = state.start + timeLimit
    let now = ContinuousClock.now
    return now < deadline ? (deadline - now) : .zero
  }

  package func isTransient(_ error: RequestError) -> Bool {
    switch error {
    case .io:
      return self.retryOnIO
    case .http(let details):
      return [408, 429, 500, 502, 503, 504].contains(details.statusCode)
    case .service(let details):
      return self.retryableCodes.contains(details.code)
    case .exhausted, .badURL, .unimplemented, .binding, .malformedResponse:
      return false
    @unknown default:
      return false
    }
  }
}

package func defaultPubSubSubchannelCount() -> Int {
  min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4)
}
