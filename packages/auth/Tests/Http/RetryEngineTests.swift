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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import GoogleCloudAuth

// MARK: - Thread-Safe Concurrency Counter for Swift 6 @Sendable Captures

// MARK: - Suite: RetryEngine Test

@Suite struct RetryEngineTest {
  private let testURL = URL(string: "https://example.com")!
  @Test func retrySucceedsOnFirstAttempt() async throws {
    let attempts = CallCounter()
    let result = try await RetryEngine.retry(
      isRetryable: { _ in true }
    ) {
      attempts.increment()
      return "success"
    }

    #expect(result == "success")
    #expect(attempts.getCount() == 1)
  }

  @Test func retryRecoversOnTransientError() async throws {
    let attempts = CallCounter()
    let config = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .seconds(0.01),
      multiplier: 1.5,
      maxDelay: .seconds(0.1)
    )

    let result = try await RetryEngine.retry(
      configuration: config,
      isRetryable: { error in
        if let httpError = error as? AuthHTTPError {
          return httpError.statusCode == 503
        }
        return false
      }
    ) {
      attempts.increment()
      if attempts.getCount() < 3 {
        throw AuthHTTPError.unsuccessfulResponse(
          response: HTTPURLResponse(
            url: self.testURL, statusCode: 503, httpVersion: nil, headerFields: nil)!, data: Data())
      }
      return "recovered"
    }

    #expect(result == "recovered")
    #expect(attempts.getCount() == 3)
  }

  @Test func retryFailsOnPermanentError() async throws {
    let attempts = CallCounter()
    let config = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .seconds(0.01),
      multiplier: 1.5,
      maxDelay: .seconds(0.1)
    )

    await #expect(throws: AuthHTTPError.self) {
      try await RetryEngine.retry(
        configuration: config,
        isRetryable: { error in
          if let httpError = error as? AuthHTTPError {
            return httpError.statusCode == 503
          }
          return false
        }
      ) {
        attempts.increment()
        throw AuthHTTPError.unsuccessfulResponse(
          response: HTTPURLResponse(
            url: self.testURL, statusCode: 404, httpVersion: nil, headerFields: nil)!, data: Data())
      }
    }

    #expect(attempts.getCount() == 1)
  }

  @Test func retryExhaustsAttempts() async throws {
    let attempts = CallCounter()
    let config = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .seconds(0.01),
      multiplier: 2.0,
      maxDelay: .seconds(0.1)
    )

    await #expect(throws: AuthHTTPError.self) {
      try await RetryEngine.retry(
        configuration: config,
        isRetryable: { error in
          if let httpError = error as? AuthHTTPError {
            return httpError.statusCode == 503
          }
          return false
        }
      ) {
        attempts.increment()
        throw AuthHTTPError.unsuccessfulResponse(
          response: HTTPURLResponse(
            url: self.testURL, statusCode: 503, httpVersion: nil, headerFields: nil)!, data: Data())
      }
    }

    #expect(attempts.getCount() == 2)
  }

  @Test func retryExitsImmediatelyOnCancellation() async throws {
    let config = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .seconds(1.0),
      multiplier: 2.0,
      maxDelay: .seconds(2.0)
    )

    let task = Task {
      try await RetryEngine.retry(
        configuration: config,
        isRetryable: { _ in true }
      ) {
        throw URLError(.badServerResponse)
      }
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test func retryObeysMaxDelayCap() async throws {
    let attempts = CallCounter()
    let config = RetryConfiguration(
      maxAttempts: 4,
      initialDelay: .seconds(0.01),
      multiplier: 2.0,
      maxDelay: .seconds(0.02)
    )

    let startTime = Date()

    await #expect(throws: URLError.self) {
      try await RetryEngine.retry(
        configuration: config,
        isRetryable: { _ in true }
      ) {
        attempts.increment()
        throw URLError(.badServerResponse)
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    #expect(attempts.getCount() == 4)
    // Delays should be: ~0.01, ~0.02, ~0.02 (capped)
    // With full jitter, total duration can be very short, so we only check upper bound.
    #expect(duration <= 0.1)
  }

  @Test func retryCancelledDuringSleep() async throws {
    let attempts = CallCounter()
    let clock = TestClock()
    let config = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .seconds(0.5),
      multiplier: 2.0,
      maxDelay: .seconds(1.0)
    )

    let task = Task {
      try await RetryEngine.retry(
        configuration: config,
        clock: clock,
        isRetryable: { _ in true }
      ) {
        attempts.increment()
        throw URLError(.badServerResponse)
      }
    }

    // Wait for the task to enter sleep in RetryEngine deterministically
    await clock.sleeperWaiting()

    // Now it is sleeping in RetryEngine!
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    #expect(attempts.getCount() == 1)
  }
}

// MARK: - Suite: AuthHTTPClient Tests
