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
}
