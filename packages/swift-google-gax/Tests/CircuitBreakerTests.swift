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

import GoogleCloudGax

@Suite struct CircuitBreakerTests {
  @Test func construction() throws {
    #expect(throws: RetryThrottlerError.tooFewMinTokens(min: 200, initial: 100)) {
      try CircuitBreaker(tokens: 100, minTokens: 200, errorCost: 1)
    }
    let _ = CircuitBreaker()
  }

  @Test func basics() throws {
    let throttler = try CircuitBreaker(tokens: 100, minTokens: 50, errorCost: 10)
    let error = RequestError.unimplemented

    // No throttling initially
    #expect(!throttler.throttleRetryAttempt())

    // The first 4 failures should succeed (100 -> 90 -> 80 -> 70 -> 60)
    for _ in 0..<4 {
      throttler.onRetryFailure(flow: .retry(error))
      #expect(!throttler.throttleRetryAttempt(), "\(throttler)")
    }
    // Two more failures get us to 50 tokens, which cause throttling:
    throttler.onRetryFailure(flow: .retry(error))
    throttler.onRetryFailure(flow: .retry(error))
    #expect(throttler.throttleRetryAttempt(), "\(throttler)")

    // 10 successes are not enough.
    for _ in 0..<10 {
      throttler.onSuccess()
      #expect(throttler.throttleRetryAttempt(), "\(throttler)")
    }
    // Finally this puts us over the minimum number of tokens:
    throttler.onSuccess()
    #expect(!throttler.throttleRetryAttempt(), "\(throttler)")

    // Permanent errors also help recovery
    throttler.onRetryFailure(flow: .retry(error))
    #expect(throttler.throttleRetryAttempt())
    for _ in 0..<9 {
      throttler.onRetryFailure(flow: .permanent(error))
      #expect(throttler.throttleRetryAttempt())
    }
    throttler.onRetryFailure(flow: .permanent(error))
    #expect(!throttler.throttleRetryAttempt())
  }
}
