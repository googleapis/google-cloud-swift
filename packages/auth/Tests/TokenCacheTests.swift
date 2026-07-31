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
import Testing

@testable import GoogleCloudAuth

// MARK: - Mock Concurrency-Safe Token Provider Actor

private actor MockTokenProvider: TokenProvider {
  private var fetchCount = 0
  private var nextToken: Token?
  private var nextError: Error?
  private var fetchContinuations: [CheckedContinuation<Void, Never>] = []
  private var fetchIsStarted = false

  func configure(token: Token?, error: Error? = nil) {
    self.nextToken = token
    self.nextError = error
  }

  func fetchToken() async throws -> Token {
    self.fetchCount += 1

    let continuationsToResume = self.fetchContinuations
    self.fetchContinuations.removeAll()

    if continuationsToResume.isEmpty {
      self.fetchIsStarted = true
    } else {
      self.fetchIsStarted = false
      for continuation in continuationsToResume {
        continuation.resume()
      }
    }

    if let error = self.nextError {
      throw error
    }
    guard let token = self.nextToken else {
      throw URLError(.unknown)
    }
    return token
  }

  /// Suspends the calling task until a fetch operation starts on this provider.
  /// If a fetch is already active, this returns immediately.
  ///
  /// ### Cooperative Continuation-Driven Waiting
  /// This method suspends the test thread by queuing a `CheckedContinuation` inside
  /// `fetchContinuations`. When the production code triggers `fetchToken()`, it registers
  /// the fetch event and resumes all pending fetch continuations in the queue, allowing the
  /// test thread to wake up and proceed deterministically.
  func fetcherWaiting() async {
    if fetchIsStarted {
      fetchIsStarted = false
      return
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      if fetchIsStarted {
        fetchIsStarted = false
        continuation.resume()
      } else {
        self.fetchContinuations.append(continuation)
      }
    }
  }

  var count: Int {
    self.fetchCount
  }
}

private final class IteratorWrapper: @unchecked Sendable {
  private var iterator: AsyncStream<Result<Token, any Error>>.AsyncIterator

  init(_ stream: AsyncStream<Result<Token, any Error>>) {
    self.iterator = stream.makeAsyncIterator()
  }

  func next() async -> Result<Token, any Error>? {
    await iterator.next()
  }
}

private actor WaitingTokenProvider: TokenProvider {
  private var fetchCount = 0
  private let wrapper: IteratorWrapper
  private var fetchContinuations: [CheckedContinuation<Void, Never>] = []
  private var fetchIsStarted = false

  init(values: AsyncStream<Result<Token, any Error>>) {
    self.wrapper = IteratorWrapper(values)
  }

  func fetchToken() async throws -> Token {
    self.fetchCount += 1

    let continuationsToResume = self.fetchContinuations
    self.fetchContinuations.removeAll()

    if continuationsToResume.isEmpty {
      self.fetchIsStarted = true
    } else {
      self.fetchIsStarted = false
      for continuation in continuationsToResume {
        continuation.resume()
      }
    }

    // Await the value from the test via wrapper
    guard let result = await wrapper.next() else {
      throw URLError(.cancelled)
    }

    switch result {
    case .success(let token):
      return token
    case .failure(let error):
      throw error
    }
  }

  /// Suspends the calling task until a fetch operation starts on this provider.
  /// If a fetch is already active, this returns immediately.
  ///
  /// ### Cooperative Continuation-Driven Waiting
  /// This method suspends the test thread by queuing a `CheckedContinuation` inside
  /// `fetchContinuations`. When the production code triggers `fetchToken()`, it registers
  /// the fetch event and resumes all pending fetch continuations in the queue, allowing the
  /// test thread to wake up and proceed deterministically.
  func fetcherWaiting() async {
    if fetchIsStarted {
      fetchIsStarted = false
      return
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      if fetchIsStarted {
        fetchIsStarted = false
        continuation.resume()
      } else {
        self.fetchContinuations.append(continuation)
      }
    }
  }

  var count: Int {
    self.fetchCount
  }
}

// MARK: - Delayed Providers for Concurrency Testing

private actor DelayedTokenProvider: TokenProvider {
  private var fetchCount = 0
  private let token: Token

  init(token: Token) {
    self.token = token
  }

  func fetchToken() async throws -> Token {
    self.fetchCount += 1
    try await Task.sleep(for: .milliseconds(50))
    return self.token
  }

  var count: Int {
    self.fetchCount
  }
}

private actor DelayedFailedTokenProvider: TokenProvider {
  private var fetchCount = 0
  private let error: Error

  init(error: Error) {
    self.error = error
  }

  func fetchToken() async throws -> Token {
    self.fetchCount += 1
    try await Task.sleep(for: .milliseconds(50))
    throw self.error
  }

  var count: Int {
    self.fetchCount
  }
}

// MARK: - Suite: TokenCache Tests

@Suite struct TokenCacheTest {
  @Test func cacheFetchesTokenWhenEmpty() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedToken = Token(
      accessToken: "token-1", expirationDate: Date().addingTimeInterval(1000))
    await provider.configure(token: expectedToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    let token = try await cache.token()
    #expect(token.accessToken == "token-1")
    #expect(await provider.count == 1)
  }

  @Test func cacheReturnsCachedTokenWhenValid() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedToken = Token(
      accessToken: "token-1", expirationDate: Date().addingTimeInterval(1000))
    await provider.configure(token: expectedToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // First call fetches from provider
    let token1 = try await cache.token()
    #expect(token1.accessToken == "token-1")

    // Second call returns cached value instantly
    let token2 = try await cache.token()
    #expect(token2.accessToken == "token-1")
    #expect(await provider.count == 1)  // Count remains 1
  }

  @Test func refreshTransientFailurePreservesValidToken() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Initial token expires in 10 seconds
    let initialToken = Token(accessToken: "valid", expirationDate: now.addingTimeInterval(10))
    await provider.configure(token: initialToken, error: nil)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // refresh when < 2s left
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in true }  // Transient errors
    )

    // Wait for the background loop to fetch the initial token
    await clock.sleeperWaiting()

    // Configure a transient error
    await provider.configure(token: nil, error: URLError(.timedOut))

    // Advance to 1 second before expiration (stale, triggers refresh)
    timeSource.advance(by: 9)
    clock.advance(by: .seconds(9))

    // Wait for the refresh loop to attempt refresh, hit the transient error, and sleep again deterministically
    await clock.sleeperWaiting()

    // The token is still valid for 1 more second. Should return cached.
    let stillValid = try await cache.token()
    #expect(stillValid.accessToken == "valid")
    #expect(await provider.count == 2)
  }

  @Test func refreshPermanentFailurePreservesValidToken() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Initial token expires in 10 seconds
    let initialToken = Token(accessToken: "valid", expirationDate: now.addingTimeInterval(10))
    await provider.configure(token: initialToken, error: nil)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // refresh when < 2s left
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in false }  // Treat all errors as permanent
    )

    // Wait for the background loop to fetch the initial token and sleep
    await clock.sleeperWaiting()

    // Configure a permanent error for the refresh
    await provider.configure(token: nil, error: URLError(.badServerResponse))

    // Advance to 1 second before expiration (stale, triggers refresh)
    timeSource.advance(by: 9)
    clock.advance(by: .seconds(9))

    // Wait for the refresh loop to attempt refresh and fail permanently.
    // It terminates instead of sleeping, so we poll provider count.
    while await provider.count < 2 {
      await Task.yield()
    }

    // The token is still valid for 1 more second! It should NOT throw yet.
    let stillValid = try await cache.token()
    #expect(stillValid.accessToken == "valid")

    // Advance past expiration
    timeSource.advance(by: 2)

    // Now it should throw the permanent error
    await #expect(throws: URLError.self) {
      try await cache.token()
    }
  }

  @Test func noRequestsAfterPermanentError() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let initialToken = Token(accessToken: "valid", expirationDate: now.addingTimeInterval(10))
    await provider.configure(token: initialToken, error: nil)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in false }
    )

    await clock.sleeperWaiting()

    await provider.configure(token: nil, error: URLError(.badServerResponse))

    // Advance to 1 second before expiration (stale, triggers refresh).
    // Loop wakes up, fails permanently, and terminates.
    timeSource.advance(by: 9)
    clock.advance(by: .seconds(9))

    while await provider.count < 2 {
      await Task.yield()
    }

    // Call token() before expiration. Should return cached token and NOT trigger another refresh.
    let stillValid = try await cache.token()
    #expect(stillValid.accessToken == "valid")
    #expect(await provider.count == 2)

    // Call token() again before expiration. Should still NOT trigger another refresh.
    _ = try await cache.token()
    #expect(await provider.count == 2)

    // Advance past expiration.
    timeSource.advance(by: 2)

    // Caller 1 hits permanent error
    await #expect(throws: URLError.self) { try await cache.token() }

    // Caller 2 hits permanent error
    await #expect(throws: URLError.self) { try await cache.token() }

    // Verify no further network requests were made even after expiration!
    #expect(await provider.count == 2)
  }

  @Test func cacheRefreshesWhenTokenIsStale() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let staleToken = Token(
      accessToken: "stale-token", expirationDate: timeSource.now.addingTimeInterval(1.5))
    await provider.configure(token: staleToken)

    // Use very short slack values for testing!
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // Consider stale if expires in < 2s
      shortRefreshSlack: .seconds(1)  // Poll every 1s if stale!
    )

    // Wait for the first fetch to complete and loop to sleep
    await clock.sleeperWaiting()

    let token1 = try await cache.token()
    #expect(token1.accessToken == "stale-token")

    let freshToken = Token(
      accessToken: "fresh-token", expirationDate: timeSource.now.addingTimeInterval(1000))
    await provider.configure(token: freshToken)

    // Advance time source FIRST, then clock!
    timeSource.advance(by: 2.0)
    clock.advance(by: .seconds(2))

    // Wait for the background loop to complete second fetch and enter sleep again deterministically
    await clock.sleeperWaiting()

    // Second call should return the fresh token!
    let token2 = try await cache.token()
    #expect(token2.accessToken == "fresh-token")
    #expect(await provider.count == 2)
  }

  @Test func concurrentCallsShareActiveTaskPreventingThunderingHerds() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedToken = Token(
      accessToken: "shared-token", expirationDate: Date().addingTimeInterval(1000))
    await provider.configure(token: expectedToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // Spawn 5 concurrent requests to token() simultaneously
    let results = try await withThrowingTaskGroup(of: Token.self) { group in
      for _ in 1...5 {
        group.addTask {
          try await cache.token()
        }
      }

      var tokens: [Token] = []
      for try await token in group {
        tokens.append(token)
      }
      return tokens
    }

    // Verify all 5 concurrent callers received the same token
    #expect(results.count == 5)
    for token in results {
      #expect(token.accessToken == "shared-token")
    }

    // Verify only ONE fetch operation was executed on the backend!
    #expect(await provider.count == 1)
  }

  @Test func cachePropagatesErrorAndAllowsRetries() async throws {
    let (valuesStream, valuesContinuation) = AsyncStream<Result<Token, any Error>>.makeStream()

    let provider = WaitingTokenProvider(values: valuesStream)
    let clock = TestClock()
    let expectedError = URLError(.timedOut)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // Spawn token() call in a task since it will wait
    let task = Task {
      try await cache.token()
    }

    // Wait for the first fetch to start deterministically
    await provider.fetcherWaiting()
    #expect(await provider.count == 1)

    // Allow first fetch to complete (and fail)
    valuesContinuation.yield(.failure(expectedError))

    // Now the task should throw error
    await #expect(throws: URLError.self) {
      try await task.value
    }

    // Re-configure provider to succeed with a fresh token
    let freshToken = Token(
      accessToken: "fresh-token", expirationDate: Date().addingTimeInterval(1000))

    // Second call to token() should trigger a new fetch
    let task2 = Task {
      try await cache.token()
    }

    // Wait for the second fetch to start
    await provider.fetcherWaiting()
    #expect(await provider.count == 2)

    // Allow second fetch to complete
    valuesContinuation.yield(.success(freshToken))

    let token = try await task2.value
    #expect(token.accessToken == "fresh-token")
  }

  @Test func cacheAbortsRefreshLoopOnPermanentError() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedError = URLError(.userAuthenticationRequired)
    await provider.configure(token: nil, error: expectedError)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in false }  // Treat all errors as permanent
    )

    // First attempt should fail
    await #expect(throws: URLError.self) {
      try await cache.token()
    }

    // Advance clock instead of sleeping!
    clock.advance(by: .seconds(0.5))

    // If it aborted, count should still be 1
    #expect(await provider.count == 1)
  }

  @Test func expiredTokenFailure() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let initialToken = Token(
      accessToken: "initial-token", expirationDate: now.addingTimeInterval(1.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(0.5),
      shortRefreshSlack: .seconds(1)
    )

    let token1 = try await cache.token()
    #expect(token1.accessToken == "initial-token")

    // Wait for the background loop to enter sleep deterministically
    await clock.sleeperWaiting()

    await provider.configure(token: nil, error: URLError(.badServerResponse))

    timeSource.advance(by: 1.2)
    clock.advance(by: .seconds(1.2))

    await #expect(throws: URLError.self) {
      try await cache.token()
    }
  }

  @Test func refreshTaskExpiredTokenLoop() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let expiredToken = Token(
      accessToken: "expired-token", expirationDate: now.addingTimeInterval(-10))
    await provider.configure(token: expiredToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1)
    )

    let token1 = try await cache.token()
    #expect(token1.accessToken == "expired-token")

    // Wait for the background loop to enter sleep deterministically
    await clock.sleeperWaiting()

    let freshToken = Token(
      accessToken: "fresh-token", expirationDate: now.addingTimeInterval(1000))
    await provider.configure(token: freshToken)

    timeSource.advance(by: 1.2)
    clock.advance(by: .seconds(1.2))

    let token2 = try await cache.token()
    #expect(token2.accessToken == "fresh-token")
  }

  @Test func noInitialTokenThunderingHerdSuccess() async throws {
    let expectedToken = Token(
      accessToken: "shared-token", expirationDate: Date().addingTimeInterval(1000))
    let delayedProvider = DelayedTokenProvider(token: expectedToken)
    let clock = TestClock()

    let cache = TokenCache(
      provider: delayedProvider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // Spawn 5 concurrent requests to token() simultaneously when empty
    let results = try await withThrowingTaskGroup(of: Token.self) { group in
      for _ in 1...5 {
        group.addTask {
          try await cache.token()
        }
      }

      var tokens: [Token] = []
      for try await token in group {
        tokens.append(token)
      }
      return tokens
    }

    // Verify all 5 concurrent callers received the same token
    #expect(results.count == 5)
    for token in results {
      #expect(token.accessToken == "shared-token")
    }

    // Verify only ONE fetch operation was executed on the backend!
    #expect(await delayedProvider.count == 1)
  }

  @Test func noInitialTokenThunderingHerdFailureSharesError() async throws {
    let expectedError = URLError(.timedOut)
    let delayedProvider = DelayedFailedTokenProvider(error: expectedError)
    let clock = TestClock()

    let cache = TokenCache(
      provider: delayedProvider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // Spawn 5 concurrent requests to token() simultaneously when empty and fails
    let errors = await withTaskGroup(of: Result<Token, Error>.self) { group in
      for _ in 1...5 {
        group.addTask {
          do {
            let token = try await cache.token()
            return .success(token)
          } catch {
            return .failure(error)
          }
        }
      }

      var results: [Result<Token, Error>] = []
      for await res in group {
        results.append(res)
      }
      return results
    }

    // Verify all 5 concurrent callers failed with the expected error
    #expect(errors.count == 5)
    for res in errors {
      switch res {
      case .success:
        Issue.record("Expected token fetch to fail, but it succeeded!")
      case .failure(let error):
        guard let urlError = error as? URLError else {
          Issue.record("Expected URLError, got: \(error)")
          continue
        }
        #expect(urlError.code == .timedOut)
      }
    }

    // Verify only ONE fetch operation was executed on the backend!
    #expect(await delayedProvider.count == 1)
  }

  @Test func debugTokenCache() async {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    let debugDescription = String(reflecting: cache)
    #expect(debugDescription.contains("TokenCache"))
  }

  @Test func backgroundLoopTriggersFetchOnStartup() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedToken = Token(
      accessToken: "token-1", expirationDate: Date().addingTimeInterval(1000))
    await provider.configure(token: expectedToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      shortRefreshSlack: .seconds(1)
    )

    // Wait for the first fetch to start deterministically!
    await provider.fetcherWaiting()
    #expect(await provider.count == 1)
    _ = cache  // Keep it alive!
  }

  @Test func tokenThrowsPermanentError() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let expectedError = URLError(.userAuthenticationRequired)
    await provider.configure(token: nil, error: expectedError)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in false }  // Treat all errors as permanent
    )

    // Wait for the background loop to start the fetch deterministically
    await provider.fetcherWaiting()

    // The fetch should fail immediately, setting permanentError and terminating loop.

    // Calling token() should throw the permanent error
    await #expect {
      try await cache.token()
    } throws: { error in
      guard let urlError = error as? URLError else { return false }
      return urlError.code == .userAuthenticationRequired
    }

    // Verify count is exactly 1 (the background loop's startup fetch)
    #expect(await provider.count == 1)

    // Call it again, should still throw the SAME error without calling provider
    await #expect {
      try await cache.token()
    } throws: { error in
      guard let urlError = error as? URLError else { return false }
      return urlError.code == .userAuthenticationRequired
    }

    #expect(await provider.count == 1)
  }

  @Test func refreshTaskSleepsUntilStale() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let token = Token(
      accessToken: "token-1", expirationDate: timeSource.now.addingTimeInterval(5.0))
    await provider.configure(token: token)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // Stale if expires in < 2s
      shortRefreshSlack: .seconds(1)
    )

    // Wait for the first fetch to complete and loop to sleep
    await clock.sleeperWaiting()

    // Now background loop should calculate sleep: 5.0 - 2.0 = 3.0 seconds

    // Re-configure provider to return a new token on next fetch
    let nextToken = Token(
      accessToken: "token-2", expirationDate: timeSource.now.addingTimeInterval(1000))
    await provider.configure(token: nextToken)

    // Advance clock by 1.0 seconds (less than 3.0s sleep). Should NOT have fetched again!
    timeSource.advance(by: 1.0)
    clock.advance(by: .seconds(1))
    #expect(await provider.count == 1)

    // Advance clock another 3.0 seconds (total 4.0s, well past the 3.0s sleep). Should HAVE fetched again!
    timeSource.advance(by: 3.0)
    clock.advance(by: .seconds(3))

    // Wait for the second fetch to complete and background loop to enter sleep again!
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let fetchedToken = try await cache.token()
    #expect(fetchedToken.accessToken == "token-2")
  }

  @Test func refreshLoopSleepsUntilStaleWhenValid() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Token expires in 10 seconds
    let token = Token(
      accessToken: "token-1", expirationDate: timeSource.now.addingTimeInterval(10.0))
    await provider.configure(token: token)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // Consider stale if expires in < 2s
      shortRefreshSlack: .seconds(0.5)
    )

    // Wait for the first fetch to complete and loop to sleep
    await clock.sleeperWaiting()

    // Advance clock by 7.9 seconds. Token is still valid and NOT stale (expires in 2.1s).
    timeSource.advance(by: 7.9)
    clock.advance(by: .seconds(7.9))

    // The sleeper is still sleeping because 7.9s < 8.0s deadline.
    #expect(clock.hasSleepers)

    _ = cache  // Keep it alive!
  }

  @Test func tokenFailureAbortsBackgroundLoop() async throws {
    let provider = MockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // 1. Configure provider to return a token that expires in 10 seconds
    let initialToken = Token(
      accessToken: "initial-token", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),  // Stale if expires in < 2s
      shortRefreshSlack: .seconds(1),
      isRetryable: { _ in false }  // Treat all errors as permanent
    )

    // 2. Wait for the first fetch to complete and background task to enter sleep (sleep duration: 8s)
    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    // 3. Re-configure provider to return a permanent error on next fetch
    let expectedError = URLError(.userAuthenticationRequired)
    await provider.configure(token: nil, error: expectedError)

    // 4. Advance timeSource by 11 seconds (so the token is now fully expired)
    // BUT do NOT advance clock! The background task remains asleep.
    timeSource.advance(by: 11.0)

    // 5. Call token() on-demand. Since token is expired, token() triggers a fetch.
    // This fetch fails with the permanent error, so token() should catch it,
    // set `permanentError` on the cache, and throw.
    await #expect(throws: URLError.self) {
      try await cache.token()
    }

    // 6. Now advance the clock by 8s to wake up the background task
    clock.advance(by: .seconds(8))

    // 7. The background task wakes up, enters checkStateAndTriggerRefresh,
    // hits the `if let _ = self.permanentError { return .terminate }` guard,
    // and terminates immediately WITHOUT triggering a third fetch!
    // So provider.count must remain exactly 2!
    #expect(await provider.count == 2)

    // 8. Subsequent calls to token() should instantly throw the permanent error without calling provider
    await #expect {
      try await cache.token()
    } throws: { error in
      guard let urlError = error as? URLError else { return false }
      return urlError.code == .userAuthenticationRequired
    }

    #expect(await provider.count == 2)
  }
}
