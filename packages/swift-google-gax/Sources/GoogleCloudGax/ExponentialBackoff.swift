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
public enum ExponentialBackoffError: Error {
  /// The scaling factor is invalid (must be >= 1.0).
  case invalidScalingFactor(Double)
  /// The initial delay is invalid (must be > 0).
  case invalidInitialDelay(Duration)
  /// The delay range is empty or invalid.
  case emptyRange(initial: Duration, maximum: Duration)
}

/// Configuration for ``ExponentialBackoff``.
public struct ExponentialBackoffConfig: Sendable {
  /// The initial delay before the first retry.
  public var initialDelay: Duration = .seconds(1)
  /// The maximum delay between retries.
  public var maximumDelay: Duration = .seconds(60)
  /// The scaling factor for each subsequent retry.
  public var scaling: Double = 2.0

  /// Create a new configuration with default values.
  public init() {}

  /// Override specific values using the `Then` idiom.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Implements truncated [exponential backoff] with jitter.
///
/// This class conforms to the ``BackoffPolicy`` protocol. It implements an exponential backoff
/// algorithm, where the delay between attempts grows exponentially on each attempt, typically
/// doubling. That quickly smears the retry attempts over time. To minimize the chances of
/// simultaneous retry attempts, each delay has randomized jitter. Finally, the delay is truncated
/// if it grows beyond some maximum delay.
///
/// [Exponential backoff]: https://en.wikipedia.org/wiki/Exponential_backoff
public final class ExponentialBackoff: BackoffPolicy, Sendable {
  public let initialDelay: Duration
  public let maximumDelay: Duration
  public let scaling: Double

  /// Create a new exponential backoff policy with the default configuration.
  public init() {
    let d = try! ExponentialBackoff(config: ExponentialBackoffConfig())
    self.initialDelay = d.initialDelay
    self.maximumDelay = d.maximumDelay
    self.scaling = d.scaling
  }

  /// Create a new exponential backoff policy from a configuration.
  ///
  /// - Parameter config: The configuration to use.
  /// - Throws: ``ExponentialBackoffError`` if the configuration is invalid.
  public init(config: ExponentialBackoffConfig) throws {
    if config.scaling < 1.0 {
      throw ExponentialBackoffError.invalidScalingFactor(config.scaling)
    }
    if config.initialDelay <= .seconds(0) {
      throw ExponentialBackoffError.invalidInitialDelay(config.initialDelay)
    }
    if config.maximumDelay < config.initialDelay {
      throw ExponentialBackoffError.emptyRange(
        initial: config.initialDelay, maximum: config.maximumDelay)
    }
    self.initialDelay = config.initialDelay
    self.maximumDelay = config.maximumDelay
    self.scaling = config.scaling
  }

  /// Creates a new exponential backoff policy clamping the ranges towards recommended values.
  ///
  /// The maximum delay is clamped first, to be between one second and one day (both inclusive). The
  /// initial delay is clamped to be between one millisecond and the maximum delay. The scaling
  /// factor is clamped to the `[1.0, 32.0]` range.
  ///
  /// - Parameter config: The configuration to use.
  public init(clamping config: ExponentialBackoffConfig) {
    let minScaling = 1.0
    let maxScaling = 32.0
    let minDelay: Duration = .seconds(1)
    let maxDelay: Duration = .seconds(60) * 60 * 24  // a full day is enough for everybody
    let minInitial: Duration = .milliseconds(1)

    self.scaling = min(max(config.scaling, minScaling), maxScaling)
    self.maximumDelay = min(max(config.maximumDelay, minDelay), maxDelay)
    self.initialDelay = min(max(config.initialDelay, minInitial), self.maximumDelay)
  }

  public func backoffDelayFor(_ state: RetryState) -> Duration {
    let d = delay(attemptCount: state.attemptCount)
    return Duration(attoseconds: Int128.random(in: 0...d.attoseconds))
  }

  /// Internal method to calculate the delay without jitter.
  func delay(attemptCount: UInt32) -> Duration {
    let exp = max(0, Int(attemptCount) - 1)
    let s = pow(scaling, Double(exp))
    // Avoid overflow or extremely large values before multiplying by initialDelay.
    if s >= (maximumDelay / initialDelay) {
      return maximumDelay
    }
    return initialDelay * s
  }
}
