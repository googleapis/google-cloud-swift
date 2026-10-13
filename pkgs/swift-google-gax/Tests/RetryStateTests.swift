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

import GoogleGax

@Suite struct RetryStateTests {
  @Test func defaults() {
    let now = ContinuousClock.now
    let got = RetryState()
    #expect(got.idempotent == false)
    #expect(got.attemptCount == 0)
    // We can't easily test the exact 'now' but we can check it's recent.
    #expect(got.start >= now)
    #expect(got.start <= ContinuousClock.now)
  }

  @Test func withIdempotent() {
    let got = RetryState(idempotent: true)
    #expect(got.idempotent == true)
    #expect(got.attemptCount == 0)
  }

  @Test func parameterizedInit() {
    let start = ContinuousClock.now - .seconds(30)
    let got = RetryState(idempotent: true, start: start, attemptCount: 3)
    #expect(got.idempotent == true)
    #expect(got.start == start)
    #expect(got.attemptCount == 3)

    let partial = RetryState(attemptCount: 4)
    #expect(partial.idempotent == false)
    #expect(partial.attemptCount == 4)
  }

  @Test func with() {
    let start = ContinuousClock.now - .seconds(60)
    let got = RetryState().with {
      $0.idempotent = true
      $0.attemptCount = 5
      $0.start = start
    }
    #expect(got.idempotent == true)
    #expect(got.attemptCount == 5)
    #expect(got.start == start)
  }

  @Test func equatableAndHashable() {
    let start = ContinuousClock.now - .seconds(60)
    let state1 = RetryState(idempotent: true, start: start, attemptCount: 2)
    let state2 = RetryState(idempotent: true, start: start, attemptCount: 2)
    let state3 = RetryState(idempotent: false, start: start, attemptCount: 2)
    let state4 = RetryState(idempotent: true, start: start, attemptCount: 3)
    let state5 = RetryState(idempotent: true, start: start + .seconds(1), attemptCount: 2)

    #expect(state1 == state2)
    #expect(state1 != state3)
    #expect(state1 != state4)
    #expect(state1 != state5)

    let set: Set<RetryState> = [state1, state2, state3, state4, state5]
    #expect(set.count == 4)
  }
}
