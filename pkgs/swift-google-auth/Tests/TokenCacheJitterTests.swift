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
import Testing

@testable import GoogleCloudAuth

// MARK: - Mock Concurrency-Safe Token Provider Actor

private actor JitterMockTokenProvider: TokenProvider {
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

// MARK: - Suite: TokenCache Jitter Tests

@Suite struct TokenCacheJitterTest {
  @Test func defaultJitterWithinRange() {
    let lower = Duration.seconds(10)
    let upper = Duration.seconds(240)
    let range = lower...upper

    for _ in 0..<100 {
      let result = TokenCache<ContinuousClock>.defaultJitter(range)
      #expect(result >= lower, "Result \(result) must be >= lowerBound \(lower)")
      #expect(result <= upper, "Result \(result) must be <= upperBound \(upper)")
    }
  }

  @Test func defaultJitterZeroWidthRange() {
    let exact = Duration.seconds(42)
    let result = TokenCache<ContinuousClock>.defaultJitter(exact...exact)
    #expect(result == exact)
  }

  @Test func defaultJitterSubsecondRange() {
    let lower = Duration.milliseconds(100)
    let upper = Duration.milliseconds(900)
    let range = lower...upper

    for _ in 0..<50 {
      let result = TokenCache<ContinuousClock>.defaultJitter(range)
      #expect(result >= lower)
      #expect(result <= upper)
    }
  }

  @Test func defaultJitterProducesVariedValues() {
    let lower = Duration.seconds(1)
    let upper = Duration.seconds(100)
    let range = lower...upper

    var uniqueResults = Set<Duration>()
    for _ in 0..<20 {
      uniqueResults.insert(TokenCache<ContinuousClock>.defaultJitter(range))
    }
    #expect(uniqueResults.count > 1, "defaultJitter should generate distinct random values")
  }

  @Test func normalRangeDeterministicJitterUpper() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Token expires in 10 seconds.
    // normalRefreshSlack = 2s, shortRefreshSlack = 1s.
    // minSleep = 10 - 2 = 8s (D).
    // maxSleep = 10 - 1 = 9s (T - shortRefreshSlack).
    let initialToken = Token(
      accessToken: "initial", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      jitter: { range in range.upperBound }
    )

    // Wait for initial fetch to finish and background loop to sleep
    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    // Prepare next token
    let refreshedToken = Token(
      accessToken: "refreshed", expirationDate: now.addingTimeInterval(3600.0))
    await provider.configure(token: refreshedToken)

    // Advance by 8.5 seconds (past D = 8.0s, but before upper bound = 9.0s)
    timeSource.advance(by: 8.5)
    clock.advance(by: .seconds(8.5))

    // Because jitter chose upperBound (9s), the background loop is STILL asleep at 8.5s!
    #expect(clock.hasSleepers)
    #expect(await provider.count == 1)

    // Advance past the 9.0s mark (0.6s more => total 9.1s)
    timeSource.advance(by: 0.6)
    clock.advance(by: .seconds(0.6))

    // Background loop wakes up, refreshes token, and sleeps for the new token's duration
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let token = try await cache.token()
    #expect(token.accessToken == "refreshed")
  }

  @Test func normalRangeDeterministicJitterLower() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let initialToken = Token(
      accessToken: "initial", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      jitter: { range in range.lowerBound }
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    let refreshedToken = Token(
      accessToken: "refreshed", expirationDate: now.addingTimeInterval(3600.0))
    await provider.configure(token: refreshedToken)

    // lowerBound is minSleep = 10 - 2 = 8.0s (D)
    timeSource.advance(by: 8.1)
    clock.advance(by: .seconds(8.1))

    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let token = try await cache.token()
    #expect(token.accessToken == "refreshed")
  }

  @Test func normalRangeDeterministicJitterClamping() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let initialToken = Token(
      accessToken: "initial", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    // Jitter returns a value far beyond upperBound (e.g. 100 seconds)
    // TokenCache should clamp it to maxSleep = 9.0s
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      jitter: { _ in .seconds(100) }
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    let refreshedToken = Token(
      accessToken: "refreshed", expirationDate: now.addingTimeInterval(3600.0))
    await provider.configure(token: refreshedToken)

    // At 8.9s, it should still be sleeping (clamped to 9.0s)
    timeSource.advance(by: 8.9)
    clock.advance(by: .seconds(8.9))
    #expect(clock.hasSleepers)
    #expect(await provider.count == 1)

    // At 9.1s, it should have awakened and refreshed
    timeSource.advance(by: 0.2)
    clock.advance(by: .seconds(0.2))
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let token = try await cache.token()
    #expect(token.accessToken == "refreshed")
  }

  @Test func normalRangeDefaultJitterSleepsWithinExpectedRange() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Token expires in 10s. normalSlack = 4s (D = 6s), shortSlack = 1s (T - 1s = 9s).
    let initialToken = Token(
      accessToken: "initial", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(4),
      shortRefreshSlack: .seconds(1),
      jitter: TokenCache<TestClock>.defaultJitter
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    let refreshedToken = Token(
      accessToken: "refreshed", expirationDate: now.addingTimeInterval(3600.0))
    await provider.configure(token: refreshedToken)

    // At 5.9s (before D = 6.0s), sleeper must ALWAYS still be sleeping
    timeSource.advance(by: 5.9)
    clock.advance(by: .seconds(5.9))
    #expect(clock.hasSleepers)
    #expect(await provider.count == 1)

    // Advancing past 9.0s (total 9.1s) must ALWAYS have awakened the sleeper
    timeSource.advance(by: 3.2)
    clock.advance(by: .seconds(3.2))
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let token = try await cache.token()
    #expect(token.accessToken == "refreshed")
  }

  @Test func shortSlackRangeJitter() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Token expires in 3 seconds.
    // normalSlack = 4s, shortSlack = 1s.
    // Since duration (3s) <= normalSlack (4s) and duration (3s) > shortSlack (1s),
    // it enters the short-slack range with range 0...shortSlack (0...1s).
    let initialToken = Token(
      accessToken: "stale-initial", expirationDate: now.addingTimeInterval(3.0))
    await provider.configure(token: initialToken)

    let recordedRanges = Mutex<[ClosedRange<Duration>]>([])
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(4),
      shortRefreshSlack: .seconds(1),
      jitter: { range in
        recordedRanges.withLock { $0.append(range) }
        return range.upperBound
      }
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)
    let ranges = recordedRanges.withLock { $0 }
    #expect(!ranges.isEmpty)
    #expect(ranges[0].lowerBound == .zero)
    #expect(ranges[0].upperBound == .seconds(1))

    _ = cache
  }

  @Test func nearExpiryRangeJitter() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Token expires in 0.5s (< shortRefreshSlack = 1.0s).
    // It enters the near-expiry range [T - shortSlack, T].
    let initialToken = Token(
      accessToken: "about-to-expire", expirationDate: now.addingTimeInterval(0.5))
    await provider.configure(token: initialToken)

    let recordedRanges = Mutex<[ClosedRange<Duration>]>([])
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(4),
      shortRefreshSlack: .seconds(1),
      jitter: { range in
        recordedRanges.withLock { $0.append(range) }
        return range.upperBound
      }
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)
    let ranges = recordedRanges.withLock { $0 }
    #expect(!ranges.isEmpty)
    #expect(ranges[0].lowerBound == .zero)
    #expect(ranges[0].upperBound <= .seconds(1))

    _ = cache
  }

  @Test func transientRetryJitter() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    let initialToken = Token(
      accessToken: "valid", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let retryJitterRanges = Mutex<[ClosedRange<Duration>]>([])
    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      jitter: { range in
        if range.lowerBound == .zero && range.upperBound == .seconds(1) {
          retryJitterRanges.withLock { $0.append(range) }
        }
        return range.upperBound
      },
      isRetryable: { _ in true }
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    // Configure a transient failure for the upcoming refresh
    await provider.configure(token: nil, error: URLError(.timedOut))

    // Advance clock to trigger refresh (minSleep = 8s, maxSleep = 9s; with upperBound jitter, sleep is 9s)
    timeSource.advance(by: 9.1)
    clock.advance(by: .seconds(9.1))

    // Background loop wakes up, calls fetchToken, hits transient error,
    // and sleeps with retry jitter (upperBound = 1s)
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)
    #expect(
      retryJitterRanges.withLock { !$0.isEmpty },
      "Transient retry must invoke jitter with 0...shortSlack")

    _ = cache
  }

  @Test func nilJitterPreservesExactDurations() async throws {
    let provider = JitterMockTokenProvider()
    let clock = TestClock()
    let now = Date()
    let timeSource = MockTimeSource(currentDate: now)

    // Initial token expires in 10 seconds.
    let initialToken = Token(
      accessToken: "valid", expirationDate: now.addingTimeInterval(10.0))
    await provider.configure(token: initialToken)

    let cache = TokenCache(
      provider: provider,
      clock: clock,
      timeSource: timeSource,
      normalRefreshSlack: .seconds(2),
      shortRefreshSlack: .seconds(1),
      jitter: nil  // Explicit nil jitter
    )

    await clock.sleeperWaiting()
    #expect(await provider.count == 1)

    // Configure next token
    let refreshedToken = Token(
      accessToken: "refreshed", expirationDate: now.addingTimeInterval(3600.0))
    await provider.configure(token: refreshedToken)

    // Advance to 7.9s (before D = 8.0s) -> still sleeping
    timeSource.advance(by: 7.9)
    clock.advance(by: .seconds(7.9))
    #expect(clock.hasSleepers)
    #expect(await provider.count == 1)

    // Advance by 0.2s (total 8.1s) -> woke up at exactly 8.0s and refreshed!
    timeSource.advance(by: 0.2)
    clock.advance(by: .seconds(0.2))
    await clock.sleeperWaiting()
    #expect(await provider.count == 2)

    let token = try await cache.token()
    #expect(token.accessToken == "refreshed")
  }
}
