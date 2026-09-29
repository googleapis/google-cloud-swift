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
@testable import Endurance
import Testing

@Suite struct RetryPolicyDecoratorTests {
  private struct StubRetryPolicy: RetryPolicy {
    let errorResult: RetryResult
    let throttleResult: ThrottleResult
    let remaining: Duration?

    func onError(state: RetryState, error: RequestError) -> RetryResult {
      errorResult
    }

    func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
      throttleResult
    }

    func remainingTime(state: RetryState) -> Duration? {
      remaining
    }
  }

  @Test func countsAndDelegates() {
    let counter = RetryAttemptCounter()
    let sampleError = RequestError.io(CancellationError())
    let state = RetryState(idempotent: true).with { $0.attemptCount = 1 }

    let retryDecorator = StubRetryPolicy(
      errorResult: .retry(sampleError),
      throttleResult: .retry(sampleError),
      remaining: .seconds(42)
    ).countedAndLogged(counter: counter, methodName: "testMethod", task: "testTask")

    if case .retry = retryDecorator.onError(state: state, error: sampleError) {
      // expected
    } else {
      Issue.record("Expected .retry result")
    }
    #expect(counter.value == 1)
    #expect(retryDecorator.remainingTime(state: state) == .seconds(42))
    if case .retry = retryDecorator.onThrottle(state: state, error: sampleError) {
      // expected
    } else {
      Issue.record("Expected .retry throttle result")
    }

    let exhaustedDecorator = StubRetryPolicy(
      errorResult: .exhausted(sampleError),
      throttleResult: .exhausted(sampleError),
      remaining: nil
    ).countedAndLogged(counter: counter, methodName: "testMethod", task: "testTask")

    if case .exhausted = exhaustedDecorator.onError(state: state, error: sampleError) {
      // expected
    } else {
      Issue.record("Expected .exhausted result")
    }
    #expect(counter.value == 2)
    #expect(exhaustedDecorator.remainingTime(state: state) == nil)
  }
}
