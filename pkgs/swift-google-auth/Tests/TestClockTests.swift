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

@testable import GoogleCloudAuth

// MARK: - Helper Counter

private actor Counter {
  var count = 0
  func increment() { count += 1 }
}

// MARK: - Suite: TestClockTests

@Suite struct TestClockTests {
  @Test func sleep() async throws {
    let clock = TestClock()
    let start = clock.now
    let completed = Counter()

    Task {
      try await clock.sleep(until: start.advanced(by: .seconds(3)))
      await completed.increment()
    }

    #expect(await completed.count == 0)

    clock.advance(by: .seconds(1))
    #expect(await completed.count == 0)

    clock.advance(by: .seconds(1))
    #expect(await completed.count == 0)

    clock.advance(by: .seconds(1))

    // Wait for background task to complete
    while await completed.count < 1 {
      try await Task.sleep(for: .seconds(0.05))
    }

    #expect(await completed.count == 1)
  }

  @Test func sleepCancel() async throws {
    let clock = TestClock()
    let start = clock.now

    let task = Task {
      try await clock.sleep(until: start.advanced(by: .seconds(3)))
    }

    clock.advance(by: .seconds(1))
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test func sleepCancelBeforeAdvance() async throws {
    let clock = TestClock()
    let start = clock.now

    let task = Task {
      try await clock.sleep(until: start.advanced(by: .seconds(3)))
    }

    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }
}
