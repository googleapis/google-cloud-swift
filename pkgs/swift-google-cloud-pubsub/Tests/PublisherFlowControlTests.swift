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

import Testing
@testable import GoogleCloudPubSub

@Suite struct PublisherFlowControlTests {
  @Test func ignoreBehaviorNeverTracksOrRejects() async throws {
    let controller = PublisherFlowController(
      PublisherFlowControlOptions().with {
        $0.maxPendingMessages = 1
        $0.maxPendingBytes = 10
        $0.limitExceededBehavior = .ignore
      })
    var permits: [PublishPermit] = []
    for _ in 0..<10 {
      permits.append(try await controller.acquire(bytes: 500))
    }
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))
    for permit in permits {
      controller.release(permit)
    }
  }

  @Test func signalErrorRejectsWithoutLeakingPermits() async throws {
    let controller = PublisherFlowController(
      PublisherFlowControlOptions().with {
        $0.maxPendingMessages = 1
        $0.maxPendingBytes = 100
        $0.limitExceededBehavior = .signalError
      })
    let first = try await controller.acquire(bytes: 60)
    #expect(controller.snapshot == (pendingMessages: 1, pendingBytes: 60))

    await #expect {
      _ = try await controller.acquire(bytes: 10)
    } throws: { error in
      if case PubSubError.flowControlLimitExceeded(.messageCount(pending: 2, limit: 1)) = error {
        return true
      }
      return false
    }

    controller.release(first)
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))

    await #expect {
      _ = try await controller.acquire(bytes: 200)
    } throws: { error in
      if case PubSubError.flowControlLimitExceeded(.byteCount(pendingBytes: 200, limitBytes: 100)) =
        error
      {
        return true
      }
      return false
    }
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))
  }

  @Test func blockEnforcesFIFONonBypassAndAllowsIdleOversized() async throws {
    let controller = PublisherFlowController(
      PublisherFlowControlOptions().with {
        $0.maxPendingMessages = 10
        $0.maxPendingBytes = 100
        $0.limitExceededBehavior = .block
      })

    // Idle oversized exception admits one large message when pending == 0.
    let oversized = try await controller.acquire(bytes: 250)
    controller.release(oversized)
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))

    let order = TestBox<[String]>([])
    let p1 = try await controller.acquire(bytes: 60)

    let waiterBig = Task {
      let permit = try await controller.acquire(bytes: 70)
      order.withLock { $0.append("b2") }
      return permit
    }
    // Wait until waiterBig is queued before queuing smaller waiterSmall.
    try await Task.sleep(for: .milliseconds(20))

    let waiterSmall = Task {
      let permit = try await controller.acquire(bytes: 40)
      order.withLock { $0.append("s1") }
      return permit
    }
    try await Task.sleep(for: .milliseconds(20))
    // Even though 60 + 40 <= 100, FIFO ordering prevents waiterSmall from bypassing waiterBig.
    #expect(order.withLock { $0 }.isEmpty)

    controller.release(p1)
    let pBig = try await waiterBig.value
    try await Task.sleep(for: .milliseconds(20))
    // 70 + 40 = 110 > 100, so waiterSmall must still wait until pBig is released.
    #expect(order.withLock { $0 } == ["b2"])

    controller.release(pBig)
    let pSmall = try await waiterSmall.value
    #expect(order.withLock { $0 } == ["b2", "s1"])
    controller.release(pSmall)
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))
  }

  @Test func cancelledBlockWaiterDoesNotLeakOrStallSubsequentWaiters() async throws {
    let controller = PublisherFlowController(
      PublisherFlowControlOptions().with {
        $0.maxPendingMessages = 1
        $0.maxPendingBytes = 100
        $0.limitExceededBehavior = .block
      })

    let p1 = try await controller.acquire(bytes: 90)
    let cancelledTask = Task {
      try await controller.acquire(bytes: 50)
    }
    try await Task.sleep(for: .milliseconds(20))
    let secondTask = Task {
      try await controller.acquire(bytes: 50)
    }
    try await Task.sleep(for: .milliseconds(20))

    cancelledTask.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await cancelledTask.value
    }

    controller.release(p1)
    let p2 = try await secondTask.value
    controller.release(p2)
    #expect(controller.snapshot == (pendingMessages: 0, pendingBytes: 0))
  }

  @Test func hedgingTokenBucketStartsEmptyRefillsFractionallyAndCaps() {
    let bucket = HedgingTokenBucket(
      HedgingOptions().with {
        $0.isEnabled = true
        $0.maxTokens = 1
        $0.refillRatio = 0.2
      })
    #expect(bucket.currentMilliTokens == 0)
    #expect(!bucket.tryConsumeHedgeToken())

    for _ in 0..<4 {
      bucket.recordSuccess()
    }
    #expect(bucket.currentMilliTokens == 800)
    #expect(!bucket.tryConsumeHedgeToken())

    bucket.recordSuccess()
    #expect(bucket.currentMilliTokens == 1_000)

    // Exceeding maxTokens caps at 1_000 (1 token).
    for _ in 0..<10 {
      bucket.recordSuccess()
    }
    #expect(bucket.currentMilliTokens == 1_000)

    #expect(bucket.tryConsumeHedgeToken())
    #expect(bucket.currentMilliTokens == 0)
    #expect(!bucket.tryConsumeHedgeToken())
  }
}
