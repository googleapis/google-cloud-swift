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
import GoogleRpc
import Synchronization
import Testing
@_spi(GoogleCloudInternal) import GoogleCloudGax

@Suite struct RetryLoopTest {
  func permanent() -> RequestError {
    RequestError.service(ServiceError(code: Code.permissionDenied, message: "oh-oh"))
  }

  func transient() -> RequestError {
    RequestError.service(ServiceError(code: Code.unavailable, message: "try-again"))
  }

  @Test func immediateSuccess() async throws {
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { _, e in .retry(e) }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    let response = try await loop.run(
      inner: { _ in "success" },
      sleep: { _ in }
    )

    #expect(response == "success")
  }

  @Test func immediateFailure() async throws {
    let error = permanent()
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { _, e in .permanent(e) }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in throw error },
        sleep: { _ in }
      )
    }
  }

  struct CustomDomainError: Error, Equatable {}

  @Test func nonRequestErrorThrownDirectly() async throws {
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { _, e in .retry(e) }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    await #expect(throws: CustomDomainError.self) {
      try await loop.run(
        inner: { _ in throw CustomDomainError() },
        sleep: { _ in }
      )
    }
  }

  @Test func retrySuccess() async throws {
    let transientError = transient()
    var attempts = 0
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { _, e in .retry(e) }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    let response = try await loop.run(
      inner: { _ in
        attempts += 1
        if attempts < 3 {
          throw transientError
        }
        return "success"
      },
      sleep: { _ in }
    )

    #expect(response == "success")
    #expect(attempts == 3)
  }

  @Test func tooManyTransients() async throws {
    let transientError = transient()
    var attempts = 0
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { state, e in
        state.attemptCount < 3 ? .retry(e) : .exhausted(e)
      }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in
          attempts += 1
          throw transientError
        },
        sleep: { _ in }
      )
    }
    #expect(attempts == 3)
  }

  @Test func transientThenPermanent() async throws {
    let transientError = transient()
    let permanentError = permanent()
    var attempts = 0
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(onError: { _, e in
        if case .service(let details) = e, details.code == .unavailable {
          return .retry(e)
        }
        return .permanent(e)
      }),
      backoffPolicy: MockBackoff(),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in
          attempts += 1
          if attempts == 1 { throw transientError }
          throw permanentError
        },
        sleep: { _ in }
      )
    }
    #expect(attempts == 2)
  }

  @Test func throttleThenSuccess() async throws {
    let transientError = transient()
    var attempts = 0
    var sleeps = 0
    let throttler = MockThrottler(shouldThrottle: [true, false])
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(
        onError: { _, e in .retry(e) },
        onThrottle: { _, e in .retry(e) }
      ),
      backoffPolicy: MockBackoff(),
      retryThrottler: throttler,
      idempotent: true
    )

    let response = try await loop.run(
      inner: { _ in
        attempts += 1
        if attempts == 1 { throw transientError }
        return "success"
      },
      sleep: { _ in sleeps += 1 }
    )

    #expect(response == "success")
    #expect(attempts == 2)
    // 1 sleep for backoff after first failure,
    // 1 sleep for backoff after throttle
    #expect(sleeps == 2)
  }

  @Test func throttleAndRetryPolicyStopsLoop() async throws {
    let transientError = transient()
    var attempts = 0
    let throttler = MockThrottler(shouldThrottle: [true])
    let loop = _RetryLoop(
      retryPolicy: MockPolicy(
        onError: { _, e in .retry(e) },
        onThrottle: { _, e in .exhausted(e) }
      ),
      backoffPolicy: MockBackoff(),
      retryThrottler: throttler,
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in
          attempts += 1
          throw transientError
        },
        sleep: { _ in }
      )
    }
    #expect(attempts == 1)
  }

  @Test func noSleepPastOverallTimeout() async throws {
    let transientError = transient()
    let remainingTimeValues: [Duration?] = [.milliseconds(100), .milliseconds(100)]
    let remainingTimeIndex = AtomicCounter()

    let loop = _RetryLoop(
      retryPolicy: MockPolicy(
        onError: { _, e in .retry(e) },
        remainingTime: { _ in
          let index = remainingTimeIndex.increment()
          return index < remainingTimeValues.count ? remainingTimeValues[index] : nil
        }
      ),
      backoffPolicy: MockBackoff(delay: .seconds(10)),
      retryThrottler: MockThrottler(),
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in throw transientError },
        sleep: { _ in }
      )
    }
  }

  @Test func noSleepPastOverallTimeoutAfterThrottle() async throws {
    let transientError = transient()
    let backoffDelays: [Duration] = [.zero, .seconds(10)]
    let backoffIndex = AtomicCounter()

    struct SeqBackoff: BackoffPolicy {
      let delays: [Duration]
      let index: AtomicCounter
      func backoffDelayFor(_ state: RetryState) -> Duration {
        let i = index.increment()
        return i < delays.count ? delays[i] : .zero
      }
    }

    let remainingTimeValues: [Duration?] = [
      .milliseconds(100), .milliseconds(100), .milliseconds(100),
    ]
    let remainingTimeIndex = AtomicCounter()

    let loop = _RetryLoop(
      retryPolicy: MockPolicy(
        onError: { _, e in .retry(e) },
        onThrottle: { _, e in .retry(e) },
        remainingTime: { _ in
          let index = remainingTimeIndex.increment()
          return index < remainingTimeValues.count ? remainingTimeValues[index] : nil
        }
      ),
      backoffPolicy: SeqBackoff(delays: backoffDelays, index: backoffIndex),
      retryThrottler: MockThrottler(shouldThrottle: [true]),
      idempotent: true
    )

    await #expect(throws: RequestError.self) {
      try await loop.run(
        inner: { _ in throw transientError },
        sleep: { _ in }
      )
    }
  }

  final class AtomicCounter: Sendable {
    private let value = Mutex(0)
    func increment() -> Int {
      value.withLock {
        let current = $0
        $0 += 1
        return current
      }
    }
  }
}
