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

@Suite struct AdaptiveThrottlerTests {
  @Test func construction() throws {
    #expect(throws: RetryThrottlerError.scalingOutOfRange(-1.0)) {
      try AdaptiveThrottler(factor: -1.0)
    }
    let _ = try AdaptiveThrottler(factor: 0.0)
  }

  @Test func defaults() throws {
    let _ = AdaptiveThrottler()
  }

  @Test func basics() throws {
    let throttler = try AdaptiveThrottler(factor: 2.0)
    let error = RequestError.unimplemented

    // No throttling initially
    #expect(!throttler.throttleRetryAttempt())

    // Success increases accept count
    throttler.onSuccess()
    #expect(!throttler.throttleRetryAttempt())

    // Permanent failure also increases accept count: it is interpreted as received by the service
    throttler.onRetryFailure(flow: .permanent(error))
    #expect(!throttler.throttleRetryAttempt())

    // Retry failures do NOT increase accept count, but increase request count
    for _ in 0..<100 {
      throttler.onRetryFailure(flow: .retry(error))
    }

    // 102 requests, 2 accepts. Prob = (102 - 2*2) / 103 = 98 / 103 ~= 0.95
    #expect(throttler.throttleRetryAttemptImpl(gen: { 0.00 }), "\(throttler)")
    #expect(throttler.throttleRetryAttemptImpl(gen: { 0.50 }), "\(throttler)")
    #expect(throttler.throttleRetryAttemptImpl(gen: { 0.90 }), "\(throttler)")
    #expect(!throttler.throttleRetryAttemptImpl(gen: { 0.99 }), "\(throttler)")
    #expect(!throttler.throttleRetryAttemptImpl(gen: { 1.00 }), "\(throttler)")
  }
}
