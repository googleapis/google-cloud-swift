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

@testable import GoogleCloudGax

@Suite struct ExponentialBackoffTests {
  @Test func defaults() throws {
    let backoff = ExponentialBackoff()
    #expect(backoff.initialDelay > .seconds(0))
    #expect(backoff.maximumDelay <= .seconds(60) * 60 * 24)
    #expect(backoff.scaling == 2.0)
  }

  @Test func configWith() throws {
    let config = ExponentialBackoffConfig().with {
      $0.initialDelay = .milliseconds(500)
      $0.maximumDelay = .seconds(10)
      $0.scaling = 1.5
    }
    let backoff = try ExponentialBackoff(config: config)
    #expect(backoff.initialDelay == .milliseconds(500))
    #expect(backoff.maximumDelay == .seconds(10))
    #expect(backoff.scaling == 1.5)
  }

  @Test func delayCalculations() throws {
    let config = ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(1)
      $0.maximumDelay = .seconds(10)
      $0.scaling = 2.0
    }
    let backoff = try ExponentialBackoff(config: config)

    #expect(backoff.delay(attemptCount: 0) == .seconds(1))
    #expect(backoff.delay(attemptCount: 1) == .seconds(1))
    #expect(backoff.delay(attemptCount: 2) == .seconds(2))
    #expect(backoff.delay(attemptCount: 3) == .seconds(4))
    #expect(backoff.delay(attemptCount: 4) == .seconds(8))
    #expect(backoff.delay(attemptCount: 5) == .seconds(10))
    #expect(backoff.delay(attemptCount: 100) == .seconds(10))
  }

  @Test func invalidConfigs() {
    #expect(throws: ExponentialBackoffError.invalidScalingFactor(0.5)) {
      try ExponentialBackoff(config: ExponentialBackoffConfig().with { $0.scaling = 0.5 })
    }
    #expect(throws: ExponentialBackoffError.invalidInitialDelay(.seconds(0))) {
      try ExponentialBackoff(
        config: ExponentialBackoffConfig().with { $0.initialDelay = .seconds(0) })
    }
    #expect(throws: ExponentialBackoffError.emptyRange(initial: .seconds(10), maximum: .seconds(5)))
    {
      try ExponentialBackoff(
        config: ExponentialBackoffConfig().with {
          $0.initialDelay = .seconds(10)
          $0.maximumDelay = .seconds(5)
        })
    }
  }

  @Test func clamping() {
    let config = ExponentialBackoffConfig().with {
      $0.initialDelay = .microseconds(100)
      $0.maximumDelay = .milliseconds(500)
      $0.scaling = 0.5
    }
    let backoff = ExponentialBackoff(clamping: config)
    #expect(backoff.scaling == 1.0)
    #expect(backoff.maximumDelay == .seconds(1))
    #expect(backoff.initialDelay == .milliseconds(1))

    let config2 = ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(100_000_000)
      $0.maximumDelay = .seconds(100_000_000)
      $0.scaling = 100.0
    }
    let backoff2 = ExponentialBackoff(clamping: config2)
    #expect(backoff2.scaling == 32.0)
    #expect(backoff2.maximumDelay == .seconds(60) * 60 * 24)
    #expect(backoff2.initialDelay == .seconds(60) * 60 * 24)
  }

  @Test func jitterRange() throws {
    let backoff = ExponentialBackoff()
    let state = RetryState().with { $0.attemptCount = 1 }
    for _ in 0..<100 {
      let d = backoff.backoffDelay(for: state)
      #expect(d >= .seconds(0) && d <= .seconds(1))
    }
  }
}

extension ExponentialBackoffError: Equatable {
  public static func == (lhs: ExponentialBackoffError, rhs: ExponentialBackoffError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidScalingFactor(let l), .invalidScalingFactor(let r)): return l == r
    case (.invalidInitialDelay(let l), .invalidInitialDelay(let r)): return l == r
    case (.emptyRange(let li, let lm), .emptyRange(let ri, let rm)): return li == ri && lm == rm
    default: return false
    }
  }
}
