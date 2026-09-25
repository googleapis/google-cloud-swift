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

@Suite struct LinearBackoffPolicyTests {
  @Test func defaults() {
    let policy = LinearBackoffPolicy()
    #expect(policy.delay == .seconds(5))
    #expect(policy.backoffDelayFor(RetryState()) == .seconds(5))
  }

  @Test func customDelay() {
    let policy = LinearBackoffPolicy(delay: .seconds(2))
    #expect(policy.delay == .seconds(2))
    #expect(policy.backoffDelayFor(RetryState()) == .seconds(2))
  }

  @Test func clamping() {
    let policy = LinearBackoffPolicy(delay: .seconds(-1))
    #expect(policy.delay == .zero)
    #expect(policy.backoffDelayFor(RetryState()) == .zero)
  }

  @Test func equatable() {
    let a = LinearBackoffPolicy(delay: .seconds(5))
    let b = LinearBackoffPolicy(delay: .seconds(5))
    #expect(a == b)
    let c = LinearBackoffPolicy(delay: .seconds(10))
    #expect(a != c)
  }
}
