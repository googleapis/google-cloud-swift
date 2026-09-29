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

@testable import Endurance
import Testing

@Suite struct MetricsTests {
  @Test func metricsTrackerOperations() async {
    let counter = RetryAttemptCounter(initialValue: 2)
    let tracker = MetricsTracker(retryAttempts: counter)

    #expect(await tracker.totalSuccessCount == 0)
    #expect(await tracker.totalErrorCount == 0)
    #expect(await tracker.totalUpdateCount == 0)

    let first = await tracker.record(successes: 10, errors: 1, updates: 2)
    #expect(first.totalSuccess == 10)
    #expect(first.totalError == 1)
    #expect(first.totalUpdate == 2)
    #expect(first.totalRetry == 2)

    await tracker.recordRetryAttempt()
    let second = await tracker.record(successes: 5, errors: 3, updates: 1)
    #expect(second.totalSuccess == 15)
    #expect(second.totalError == 4)
    #expect(second.totalUpdate == 3)
    #expect(second.totalRetry == 3)

    #expect(await tracker.totalSuccessCount == 15)
    #expect(await tracker.totalErrorCount == 4)
    #expect(await tracker.totalUpdateCount == 3)
  }

  @Test func retryAttemptCounterAtomicIncrements() async {
    let counter = RetryAttemptCounter()
    #expect(counter.value == 0)
    #expect(counter.countValue == 0)

    counter.recordRetryAttempt()
    counter.increment()
    #expect(counter.value == 2)
    #expect(counter.countValue == 2)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask {
          counter.recordRetryAttempt()
        }
      }
    }
    #expect(counter.value == 102)
  }
}
