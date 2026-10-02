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

@testable import GoogleGax

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

    #expect(backoff.delay(attemptCount: -1) == .seconds(1))
    #expect(backoff.delay(attemptCount: 0) == .seconds(1))
    #expect(backoff.delay(attemptCount: 1) == .seconds(2))
    #expect(backoff.delay(attemptCount: 2) == .seconds(4))
    #expect(backoff.delay(attemptCount: 3) == .seconds(8))
    #expect(backoff.delay(attemptCount: 4) == .seconds(10))
    #expect(backoff.delay(attemptCount: 100) == .seconds(10))
  }

  @Test func pollingBackoffDelay() throws {
    let config = ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(1)
      $0.maximumDelay = .seconds(10)
      $0.scaling = 2.0
    }
    let backoff: any PollingBackoffPolicy = try ExponentialBackoff(config: config)

    #expect(backoff.backoffDelay(for: PollingState().with { $0.attemptCount = 0 }) == .seconds(1))
    #expect(backoff.backoffDelay(for: PollingState().with { $0.attemptCount = 1 }) == .seconds(2))
    #expect(backoff.backoffDelay(for: PollingState().with { $0.attemptCount = 2 }) == .seconds(4))
    #expect(backoff.backoffDelay(for: PollingState().with { $0.attemptCount = 3 }) == .seconds(8))
    #expect(backoff.backoffDelay(for: PollingState().with { $0.attemptCount = 4 }) == .seconds(10))
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
    let state1 = RetryState().with { $0.attemptCount = 1 }
    let state2 = RetryState().with { $0.attemptCount = 2 }
    for _ in 0..<100 {
      let d1 = backoff.backoffDelay(for: state1)
      #expect(d1 >= .seconds(0) && d1 <= .seconds(1))
      let d2 = backoff.backoffDelay(for: state2)
      #expect(d2 >= .seconds(0) && d2 <= .seconds(2))
    }
  }

  @Test func equatable() throws {
    let a = ExponentialBackoff()
    let b = ExponentialBackoff()
    #expect(a == b)

    let configA = ExponentialBackoffConfig()
    let configB = ExponentialBackoffConfig()
    #expect(configA == configB)

    let custom = try ExponentialBackoff(
      config: ExponentialBackoffConfig().with { $0.scaling = 3.0 })
    #expect(a != custom)
  }

  @Test func exponentialBackoffErrorConformances() {
    let scalingErr = ExponentialBackoffError.invalidScalingFactor(0.5)
    #expect(scalingErr.description == "Invalid scaling factor: 0.5 (must be >= 1.0)")
    #expect(scalingErr.debugDescription == "ExponentialBackoffError.invalidScalingFactor(0.5)")
    let scalingLoc = scalingErr as LocalizedError
    #expect(scalingLoc.errorDescription == scalingErr.description)
    #expect(
      scalingLoc.recoverySuggestion
        == "Ensure the scaling factor is >= 1.0, the initial delay is > 0, and the initial delay does not exceed the maximum delay."
    )

    let delayErr = ExponentialBackoffError.invalidInitialDelay(.seconds(0))
    #expect(delayErr.description == "Invalid initial delay: 0.0 seconds (must be > 0)")
    #expect(
      delayErr.debugDescription == "ExponentialBackoffError.invalidInitialDelay(0.0 seconds)"
    )

    let rangeErr = ExponentialBackoffError.emptyRange(
      initial: .seconds(10), maximum: .seconds(5)
    )
    #expect(
      rangeErr.description
        == "Invalid delay range: initial delay 10.0 seconds must be <= maximum delay 5.0 seconds"
    )
    #expect(
      rangeErr.debugDescription
        == "ExponentialBackoffError.emptyRange(initial: 10.0 seconds, maximum: 5.0 seconds)"
    )

    let identical = ExponentialBackoffError.invalidScalingFactor(0.5)
    #expect(scalingErr == identical)
    #expect(scalingErr != delayErr)
  }
}
