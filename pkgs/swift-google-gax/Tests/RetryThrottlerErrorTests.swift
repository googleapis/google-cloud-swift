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
import GoogleGax
import Testing

@Suite struct RetryThrottlerErrorTests {
  @Test func factorOutOfRange() {
    let error = RetryThrottlerError.factorOutOfRange(-0.5)
    #expect(error.description == "Retry throttler factor out of range: -0.5 (must be >= 0.0)")
    #expect(error.debugDescription == "RetryThrottlerError.factorOutOfRange(-0.5)")
  }

  @Test func tooFewMinTokens() {
    let error = RetryThrottlerError.tooFewMinTokens(tokens: 10, minTokens: 20)
    #expect(error.description == "Minimum tokens (20) must be <= initial tokens (10)")
    #expect(
      error.debugDescription == "RetryThrottlerError.tooFewMinTokens(tokens: 10, minTokens: 20)")
  }

  @Test func tokensOutOfRange() {
    let error = RetryThrottlerError.tokensOutOfRange(tokens: -1, minTokens: 0, errorCost: 5)
    #expect(
      error.description
        == "Token counts and error costs must be non-negative (tokens: -1, minTokens: 0, errorCost: 5)"
    )
    #expect(
      error.debugDescription
        == "RetryThrottlerError.tokensOutOfRange(tokens: -1, minTokens: 0, errorCost: 5)"
    )
  }
}
