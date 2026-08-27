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

/// Parameters controlling exponential backoff retry behaviors.
struct RetryConfiguration: Sendable, Hashable {
  /// Maximum number of execution attempts (initial execution + retries).
  var maxAttempts: Int
  /// Initial backoff delay period.
  var initialDelay: Duration
  /// Progressive scaling multiplier factor applied to the backoff delay.
  var multiplier: Double
  /// Hard delay limit cap.
  var maxDelay: Duration

  /// Standard default retry parameters.
  static let defaultConfiguration = RetryConfiguration(
    maxAttempts: 3,
    initialDelay: .seconds(1),
    multiplier: 2.0,
    maxDelay: .seconds(60)
  )

  /// Initializes a custom retry configuration.
  ///
  /// - Parameters:
  ///   - maxAttempts: Maximum number of execution attempts.
  ///   - initialDelay: Initial backoff delay period.
  ///   - multiplier: Progressive scaling multiplier factor.
  ///   - maxDelay: Hard delay limit cap.
  init(
    maxAttempts: Int,
    initialDelay: Duration,
    multiplier: Double,
    maxDelay: Duration
  ) {
    self.maxAttempts = maxAttempts
    self.initialDelay = initialDelay
    self.multiplier = multiplier
    self.maxDelay = maxDelay
  }
}

/// A thread-safe, generic retry engine that executes an asynchronous task with exponential backoff.
///
/// ### Example Usage
/// ```swift
/// let client = AuthHTTPClient()
/// let url = URL(string: "https://oauth2.googleapis.com/token")!
///
/// struct TokenResponse: Decodable {
///   let accessToken: String
/// }
///
/// let response: TokenResponse = try await RetryEngine.retry(
///   isRetryable: { error in
///     guard let urlError = error as? URLError else { return false }
///     return urlError.code == .badServerResponse || urlError.code == .timedOut
///   }
/// ) {
///   return try await client.post(url: url, body: ["grant_type": "refresh_token"])
/// }
/// ```
enum RetryEngine: Sendable {
  /// Executes an asynchronous operation, retrying on transient errors according to the configuration.
  ///
  /// - Parameters:
  ///   - configuration: The retry parameters controlling delays and attempts.
  ///   - isRetryable: A sendable closure determining if a thrown error is transient.
  ///   - operation: The asynchronous, throwing work block to execute.
  /// - Returns: The successful outcome of the operation.
  static func retry<T: Sendable>(
    configuration: RetryConfiguration = .defaultConfiguration,
    isRetryable: @Sendable (Error) -> Bool,
    operation: @Sendable () async throws -> T
  ) async throws -> T {
    return try await retry(
      configuration: configuration, clock: ContinuousClock(), isRetryable: isRetryable,
      operation: operation)
  }

  static func retry<T: Sendable, C: Clock>(
    configuration: RetryConfiguration = .defaultConfiguration,
    clock: C,
    isRetryable: @Sendable (Error) -> Bool,
    operation: @Sendable () async throws -> T
  ) async throws -> T where C.Instant.Duration == Duration {
    var attempt = 1
    var delay = configuration.initialDelay

    while true {
      // Check for task cancellation before starting an attempt
      try Task.checkCancellation()

      do {
        return try await operation()
      } catch {
        // If task was cancelled, rethrow immediately without delaying
        if error is CancellationError {
          throw error
        }

        // Check if we have reached the maximum attempts limit, or if the error is permanent
        if attempt >= configuration.maxAttempts || !isRetryable(error) {
          throw error
        }

        // Sleep for a random duration between 0 and the current backoff delay (Full Jitter)
        let jitter = Double.random(in: 0.0...1.0)
        try await clock.sleep(for: delay * jitter)

        // Increment attempt and scale backoff delay exponentially
        attempt += 1
        delay = min(delay * configuration.multiplier, configuration.maxDelay)
      }
    }
  }
}
