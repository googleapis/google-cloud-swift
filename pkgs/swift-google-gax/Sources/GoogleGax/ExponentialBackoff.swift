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

/// The error type for exponential backoff creation.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum ExponentialBackoffError: Error, Sendable {
  /// The scaling factor is invalid (must be >= 1.0).
  case invalidScalingFactor(Double)
  /// The initial delay is invalid (must be > 0).
  case invalidInitialDelay(Duration)
  /// The delay range is empty or invalid.
  case emptyRange(initial: Duration, maximum: Duration)
}

extension ExponentialBackoffError: Equatable {}

extension ExponentialBackoffError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidScalingFactor(let scaling):
      return "Invalid scaling factor: \(scaling) (must be >= 1.0)"
    case .invalidInitialDelay(let delay):
      return "Invalid initial delay: \(delay) (must be > 0)"
    case .emptyRange(let initial, let maximum):
      return "Invalid delay range: initial delay \(initial) must be <= maximum delay \(maximum)"
    }
  }
}

extension ExponentialBackoffError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .invalidScalingFactor(let scaling):
      return "ExponentialBackoffError.invalidScalingFactor(\(scaling))"
    case .invalidInitialDelay(let delay):
      return "ExponentialBackoffError.invalidInitialDelay(\(delay))"
    case .emptyRange(let initial, let maximum):
      return "ExponentialBackoffError.emptyRange(initial: \(initial), maximum: \(maximum))"
    }
  }
}

/// Implements truncated [exponential backoff].
///
/// This struct conforms to the ``BackoffPolicy`` and ``PollingBackoffPolicy`` protocols. It
/// implements an exponential backoff algorithm, where the delay between attempts grows
/// exponentially on each attempt, typically doubling. When used as a ``BackoffPolicy`` for RPC
/// retries, each delay includes randomized jitter to minimize simultaneous retry attempts. When
/// used as a ``PollingBackoffPolicy`` for long-running operations, the delay grows without jitter.
/// Finally, the delay is truncated if it grows beyond some maximum delay.
///
/// [Exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff
public struct ExponentialBackoff: Sendable, Equatable {
  /// The initial delay before the first retry.
  public let initialDelay: Duration
  /// The maximum delay between retries.
  public let maximumDelay: Duration
  /// The scaling factor for each subsequent retry.
  public let scaling: Double

  /// Creates a new exponential backoff policy with the default configuration.
  public init() {
    self.initialDelay = .seconds(1)
    self.maximumDelay = .seconds(60)
    self.scaling = 2.0
  }

  /// Creates a new exponential backoff policy.
  ///
  /// - Parameters:
  ///   - initialDelay: The initial delay before the first retry. Defaults to 1 second.
  ///   - maximumDelay: The maximum delay between retries. Defaults to 60 seconds.
  ///   - scaling: The scaling factor for each subsequent retry. Defaults to 2.0.
  /// - Throws: ``ExponentialBackoffError`` if the configuration is invalid.
  public init(
    initialDelay: Duration = .seconds(1),
    maximumDelay: Duration = .seconds(60),
    scaling: Double = 2.0
  ) throws {
    if scaling < 1.0 {
      throw ExponentialBackoffError.invalidScalingFactor(scaling)
    }
    if initialDelay <= .seconds(0) {
      throw ExponentialBackoffError.invalidInitialDelay(initialDelay)
    }
    if maximumDelay < initialDelay {
      throw ExponentialBackoffError.emptyRange(
        initial: initialDelay, maximum: maximumDelay)
    }
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.scaling = scaling
  }

  /// Creates a new exponential backoff policy clamping the ranges towards recommended values.
  ///
  /// The maximum delay is clamped first, to be between one second and one day (both inclusive). The
  /// initial delay is clamped to be between one millisecond and the maximum delay. The scaling
  /// factor is clamped to the `[1.0, 32.0]` range.
  ///
  /// - Parameters:
  ///   - initialDelay: The initial delay before the first retry.
  ///   - maximumDelay: The maximum delay between retries. Defaults to 60 seconds.
  ///   - scaling: The scaling factor for each subsequent retry. Defaults to 2.0.
  public init(
    clamping initialDelay: Duration,
    maximumDelay: Duration = .seconds(60),
    scaling: Double = 2.0
  ) {
    let minScaling = 1.0
    let maxScaling = 32.0
    let minDelay: Duration = .seconds(1)
    let maxDelay: Duration = .seconds(60) * 60 * 24  // a full day is enough for everybody
    let minInitial: Duration = .milliseconds(1)

    self.scaling = min(max(scaling, minScaling), maxScaling)
    self.maximumDelay = min(max(maximumDelay, minDelay), maxDelay)
    self.initialDelay = min(max(initialDelay, minInitial), self.maximumDelay)
  }

  /// Internal method to calculate the delay without jitter for a 0-based attempt count.
  func delay(attemptCount: Int) -> Duration {
    let exp = max(0, attemptCount)
    let s = pow(scaling, Double(exp))
    // Avoid overflow or extremely large values before multiplying by initialDelay.
    if s >= (maximumDelay / initialDelay) {
      return maximumDelay
    }
    return initialDelay * s
  }
}
