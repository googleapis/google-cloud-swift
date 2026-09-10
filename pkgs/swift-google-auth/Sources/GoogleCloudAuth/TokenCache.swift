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

/// Represents an access token used to authenticate requests.
struct Token: Sendable, Hashable {
  /// The raw token string (e.g. access token).
  let accessToken: String
  /// The token type (e.g. "Bearer").
  let tokenType: String
  /// The date/time when the token will expire.
  let expirationDate: Date

  /// Initializes a token with an access string, token type, and expiration.
  ///
  /// - Parameters:
  ///   - accessToken: The raw token string.
  ///   - tokenType: The type of the token (defaults to "Bearer").
  ///   - expirationDate: The date/time when the token expires.
  init(accessToken: String, tokenType: String = "Bearer", expirationDate: Date) {
    self.accessToken = accessToken
    self.tokenType = tokenType
    self.expirationDate = expirationDate
  }
}

/// A type that can fetch authentication tokens from a backend source.
protocol TokenProvider: Sendable {
  /// Asynchronously fetches a fresh token from the provider.
  ///
  /// - Returns: A fresh token.
  func fetchToken() async throws -> Token
}

protocol TimeSource: Sendable {
  var now: Date { get }
}

struct SystemTimeSource: TimeSource {
  var now: Date { Date() }
}

private let defaultNormalRefreshSlack: Duration = .seconds(240)
private let defaultShortRefreshSlack: Duration = .seconds(10)

/// A thread-safe generic actor that caches and refreshes tokens on-demand.
///
/// ### How It Works
/// `TokenCache` maintains valid tokens using two core mechanisms:
///
/// 1. **Proactive Background Refresh (`backgroundTask`)**
///    Spawns on initialization to fetch new tokens *before* they expire.
///    - **Normal Operation:** Sleeps until the current token is *stale* (default: 4 mins before expiry via `normalRefreshSlack`), then refreshes it.
///    - **Transient Errors:** Retries with a short back-off (default: 10s via `shortRefreshSlack`).
///    - **Permanent Errors:** Records the error and permanently terminates the background loop.
///
/// 2. **On-Demand Access (`token()`)**
///    Provides tokens to callers while mitigating thundering herds.
///    - **Fast Path:** Instantly returns a valid cached token (even if currently stale). Under normal operation, callers never experience fetch latency.
///    - **Slow Path:** If the token is missing or fully expired, callers await an active refresh. Concurrent calls multiplex onto a single task to prevent redundant provider requests.
///    - **Fatal Errors:** If the background loop recorded a permanent error, `token()` throws it immediately without hitting the provider.
///
/// ### Memory Safety
/// The background task captures `self` weakly. It only holds a strong reference during state evaluation and releases it before sleeping on the `Clock`. This guarantees `TokenCache` can `deinit` cleanly when out of scope, which automatically cancels the background task.
actor TokenCache<C: Clock> where C.Instant.Duration == Duration {
  private let provider: any TokenProvider
  private var cachedToken: Token?
  private var activeRefreshTask: Task<Token, Error>?
  private let clock: C
  private let timeSource: any TimeSource

  private let normalRefreshSlack: Duration
  private let shortRefreshSlack: Duration
  private let isRetryable: @Sendable (Error) -> Bool
  private var permanentError: Error?

  private enum RefreshAction {
    case sleep(Duration)
    case terminate
  }

  /// Initializes the token cache with a provider, a scheduler clock, and refresh configurations.
  /// Immediately spawns the proactive background refresh loop.
  init(
    provider: any TokenProvider,
    clock: C,
    timeSource: any TimeSource = SystemTimeSource(),
    normalRefreshSlack: Duration = defaultNormalRefreshSlack,
    shortRefreshSlack: Duration = defaultShortRefreshSlack,
    isRetryable: @Sendable @escaping (Error) -> Bool = { _ in true }
  ) {
    self.provider = provider
    self.clock = clock
    self.timeSource = timeSource
    self.normalRefreshSlack = normalRefreshSlack
    self.shortRefreshSlack = shortRefreshSlack
    self.isRetryable = isRetryable

    let clock = self.clock
    let timeSource = self.timeSource

    Task { [weak self] in
      while !Task.isCancelled {
        let action: RefreshAction? = await { [weak self] in
          guard let self = self else { return nil }
          return await self.checkStateAndTriggerRefresh(timeSource: timeSource)
        }()

        guard let action = action else {
          break
        }

        switch action {
        case .sleep(let duration):
          try? await clock.sleep(for: duration)
        case .terminate:
          return
        }
      }
    }
  }

  deinit {
    activeRefreshTask?.cancel()
  }

  /// Retrieves a valid token, instantly returning cached data if available.
  ///
  /// If missing/expired, awaits the active background refresh task (sharing it concurrently to prevent thundering herds).
  func token() async throws -> Token {
    if let cached = self.cachedToken, !self.isExpired(cached) {
      return cached
    }

    if let error = self.permanentError {
      throw error
    }

    let task = self.triggerRefresh()

    do {
      let token = try await task.value
      self.updateCache(with: token)
      return token
    } catch {
      self.clearActiveTask()
      if !self.isRetryable(error) {
        self.permanentError = error
      }
      throw error
    }
  }

  // MARK: - Private Helpers

  private func isExpired(_ token: Token) -> Bool {
    return token.expirationDate <= timeSource.now
  }

  private func isStale(_ token: Token) -> Bool {
    let seconds = Double(self.normalRefreshSlack.components.seconds)
    let thresholdDate = timeSource.now.addingTimeInterval(seconds)
    return token.expirationDate <= thresholdDate
  }

  private func triggerRefresh() -> Task<Token, Error> {
    if let task = self.activeRefreshTask {
      return task
    }

    let task = Task {
      return try await self.provider.fetchToken()
    }
    self.activeRefreshTask = task
    return task
  }

  private func updateCache(with token: Token) {
    self.cachedToken = token
    self.activeRefreshTask = nil
  }

  private func clearActiveTask() {
    self.activeRefreshTask = nil
  }

  private func checkStateAndTriggerRefresh(timeSource: any TimeSource) async -> RefreshAction {
    if let _ = self.permanentError {
      return .terminate
    }

    // If we already have a valid, non-stale token, sleep until it becomes stale
    if let cached = self.cachedToken, !self.isStale(cached) {
      let timeUntilStale =
        cached.expirationDate.timeIntervalSince(timeSource.now)
        - Double(self.normalRefreshSlack.components.seconds)
      if timeUntilStale > 0 {
        return .sleep(.seconds(timeUntilStale))
      }
    }

    let task = self.triggerRefresh()

    do {
      let token = try await task.value
      self.updateCache(with: token)

      let timeUntilExpiry = token.expirationDate.timeIntervalSince(timeSource.now)
      let duration = Duration.seconds(timeUntilExpiry)

      if duration > self.normalRefreshSlack {
        return .sleep(duration - self.normalRefreshSlack)
      } else if duration > self.shortRefreshSlack {
        return .sleep(self.shortRefreshSlack)
      } else {
        return .sleep(.seconds(1))
      }
    } catch {
      if error is CancellationError {
        return .terminate
      }
      self.clearActiveTask()

      // On permanent errors, break the loop to prevent endless polling.
      if !self.isRetryable(error) {
        self.permanentError = error
        return .terminate
      }
      // Handle transient errors by sleeping and retrying
      return .sleep(self.shortRefreshSlack)
    }
  }
}

extension TokenCache where C == ContinuousClock {
  /// Initializes the cache wrapping a concrete token provider source using the system ContinuousClock.
  init(
    provider: any TokenProvider,
    normalRefreshSlack: Duration = defaultNormalRefreshSlack,
    shortRefreshSlack: Duration = defaultShortRefreshSlack,
    isRetryable: @Sendable @escaping (Error) -> Bool = { _ in true }
  ) {
    self.init(
      provider: provider,
      clock: ContinuousClock(),
      normalRefreshSlack: normalRefreshSlack,
      shortRefreshSlack: shortRefreshSlack,
      isRetryable: isRetryable
    )
  }
}

extension TokenCache: CustomDebugStringConvertible {
  nonisolated var debugDescription: String {
    return "TokenCache"
  }
}
