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
import GRPCCore
import GoogleAuth
import GoogleGax
import _GoogleCloudPubSubProtos
import SwiftProtobuf
import Testing
@testable import GoogleCloudPubSub

@Suite struct LeaseManagerTests {
  private let subscription = "projects/p/subscriptions/s"

  private func makePool(endpoint: String) throws -> GRPCChannelPool {
    let options = ClientOptions().with {
      $0.endpoint = endpoint
      $0.credentials = try? Credentials(configuration: .anonymous)
      $0.retryThrottler = CircuitBreaker()
    }
    return try GRPCChannelPool(from: options, subchannelCount: 1, environment: [:])
  }

  @Test func clampsDeadlinesAdaptsP99AndExpiresWithoutModAckZero() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try self.makePool(endpoint: server.endpoint)
    let clock = ControllableClock()
    let options = SubscribeOptions().with {
      $0.minAckExtension = .seconds(2)
      $0.maxAckExtension = .seconds(700)
      $0.maxExtension = .seconds(20)
      $0.enableAdaptiveAckExtension = true
      $0.request.retryThrottler = CircuitBreaker()
    }
    let manager = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: options,
      pool: pool,
      clock: clock
    )

    // Min is clamped [10, 600], max is clamped [10, 600].
    #expect(manager.initialExtensionSeconds(isExactlyOnce: false) == 10)

    // Train adaptive p99 histogram to 42s via ack latency.
    let releaseCount = TestBox(0)
    let slowHandler = manager.makeAckHandler(ackID: "slow-id", isExactlyOnce: false)
    let slowTracker = LeaseTracker(handler: slowHandler) {
      releaseCount.withLock { $0 += 1 }
    }
    let registeredSlow = await manager.registerBatch(
      [.init(ackID: "slow-id", leaseTracker: slowTracker)],
      isExactlyOnce: false
    )
    #expect(registeredSlow.count == 1)
    await server.waitForCalls(
      atLeast: 1,
      method: PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
    )
    #expect(server.capturedCalls[0].modAckRequest?.ackDeadlineSeconds == 10)

    clock.advance(by: .seconds(42))
    let expiredTracker = slowTracker
    // Hold across clock advance to avoid premature deinit nack; already expired!
    _ = expiredTracker
    // Wait briefly for renewal loop to expire slow-id past maxExtension=20s without ModAck(0).
    try await Task.sleep(for: .milliseconds(30))
    #expect(releaseCount.withLock { $0 } == 1)
    #expect(manager.activeLeaseCount == 0)
    #expect(
      !server.capturedCalls.contains(where: { $0.modAckRequest?.ackDeadlineSeconds == 0 }))

    // Register & ack after 45s simulated processing latency -> raises adaptive target to 45s.
    let manager2 = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.minAckExtension = .seconds(10)
        $0.maxAckExtension = .seconds(700)
        $0.maxExtension = .seconds(120)
        $0.enableAdaptiveAckExtension = true
        $0.request.retryThrottler = CircuitBreaker()
      },
      pool: pool,
      clock: clock
    )
    let hTrain = manager2.makeAckHandler(ackID: "train-id", isExactlyOnce: false)
    let tTrain = LeaseTracker(handler: hTrain)
    _ = await manager2.registerBatch(
      [.init(ackID: "train-id", leaseTracker: tTrain)],
      isExactlyOnce: false
    )
    clock.advance(by: .seconds(45))
    let ackTask = Task { try await hTrain.ackWithResult() }
    tTrain.markSettled()
    try await Task.sleep(for: .milliseconds(15))
    clock.advance(by: .milliseconds(10))
    #expect(try await ackTask.value == AckResult(status: .success))
    #expect(manager2.initialExtensionSeconds(isExactlyOnce: false) == 45)

    await manager.bulkNackRemainingAndClose(timeout: .seconds(1))
    await manager2.bulkNackRemainingAndClose(timeout: .seconds(1))
    await pool.shutdown()
  }

  @Test func chunksOver1000IDsAndOver512KiBAndIsolatesAtLeastOnceErrors() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try self.makePool(endpoint: server.endpoint)
    let clock = ControllableClock()
    let manager = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.maxExtension = .seconds(300)
        $0.request.retryThrottler = CircuitBreaker()
      },
      pool: pool,
      clock: clock
    )

    // 1) > 1,000 acks split across >= 2 Acknowledge RPCs (LEASE-01 / LEASE-05).
    var items: [LeaseManager.IncomingLeaseItem] = []
    for idx in 0..<1_005 {
      let id = "ack-bulk-\(idx)"
      let handler = manager.makeAckHandler(ackID: id, isExactlyOnce: false)
      items.append(.init(ackID: id, leaseTracker: LeaseTracker(handler: handler)))
    }
    _ = await manager.registerBatch(items, isExactlyOnce: false)
    for idx in 0..<1_005 {
      items[idx].leaseTracker.markSettled()
      _ = manager.makeAckHandler(ackID: "ack-bulk-\(idx)", isExactlyOnce: false).ack(
        options: .init())
    }
    try await Task.sleep(for: .milliseconds(20))
    clock.advance(by: .milliseconds(10))
    _ = await manager.waitForActiveLeasesToSettle(timeout: .seconds(5))

    let ackCalls = server.capturedCalls.filter {
      $0.method == PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
    }
    #expect(ackCalls.count >= 2)
    let totalAcked = ackCalls.reduce(0) { $0 + ($1.ackRequest?.ackIds.count ?? 0) }
    #expect(totalAcked == 1_005)
    for call in ackCalls {
      let req = try #require(call.ackRequest)
      #expect(req.ackIds.count <= 1_000)
      #expect(try req.serializedData().count <= LeaseManager.maxRequestBytes)
    }

    // 2) > 512 KiB IDs (540 * 1 KiB IDs) split across >= 2 Acknowledge RPCs.
    let preCount = server.capturedCalls.count
    let pad = String(repeating: "x", count: 1_000)
    var bigTasks: [Task<AckResult, any Error>] = []
    for idx in 0..<540 {
      let id = "big-\(idx)-\(pad)"
      let h = manager.makeAckHandler(ackID: id, isExactlyOnce: false)
      bigTasks.append(Task { try await h.ackWithResult() })
    }
    try await Task.sleep(for: .milliseconds(20))
    clock.advance(by: .milliseconds(10))
    for t in bigTasks {
      #expect(try await t.value == AckResult(status: .success))
    }
    let bigAckCalls = server.capturedCalls[preCount...].filter {
      $0.method == PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
    }
    #expect(bigAckCalls.count >= 2)
    for call in bigAckCalls {
      let req = try #require(call.ackRequest)
      #expect(try req.serializedData().count <= LeaseManager.maxRequestBytes)
    }

    // 3) At-least-once error isolation (`LEASE-04`): invalidArgument error resolves `.success`.
    server.setAckHandler { _, _, _ in
      throw RPCError(code: .invalidArgument, message: "alo error")
    }
    let aloHandler = manager.makeAckHandler(ackID: "alo-fail", isExactlyOnce: false)
    let aloTask = Task { try await aloHandler.ackWithResult() }
    try await Task.sleep(for: .milliseconds(20))
    clock.advance(by: .milliseconds(10))
    #expect(try await aloTask.value == AckResult(status: .success))

    await manager.bulkNackRemainingAndClose(timeout: .seconds(1))
    await pool.shutdown()
  }

  @Test func eodFloorMinOverrideReceiptModAckAndMixedBatchSplitRetry() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try self.makePool(endpoint: server.endpoint)
    let clock = ControllableClock()

    // EOD default floor = 60s, explicit 15s overrides down (`EOD-01`).
    let defaultEOD = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.request.retryThrottler = CircuitBreaker()
      },
      pool: pool,
      clock: clock
    )
    #expect(defaultEOD.initialExtensionSeconds(isExactlyOnce: true) == 60)
    let customEOD = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.minAckExtension = .seconds(15)
        $0.request.retryThrottler = CircuitBreaker()
      },
      pool: pool,
      clock: clock
    )
    #expect(customEOD.initialExtensionSeconds(isExactlyOnce: true) == 15)

    // EOD-04: mixed receipt ModAck drops permanent without retry and retries transient before returning survivors.
    let modAckAttempts = TestBox(0)
    server.setModAckHandler { req, _, _ in
      if req.ackDeadlineSeconds > 0 {
        let attempt = modAckAttempts.withLock { v -> Int in
          v += 1
          return v
        }
        if attempt == 1 {
          throw FakePubSubServer.makeEODError(
            code: .invalidArgument,
            metadata: [
              "rec-perm": "PERMANENT_FAILURE_INVALID_ACK_ID",
              "rec-surv": "TRANSIENT_FAILURE_UNORDERED_ACK_ID",
            ]
          )
        }
      }
    }

    let permReleased = TestBox(false)
    let permTracker = LeaseTracker(
      handler: defaultEOD.makeAckHandler(ackID: "rec-perm", isExactlyOnce: true)
    ) {
      permReleased.withLock { $0 = true }
    }
    let survTracker = LeaseTracker(
      handler: defaultEOD.makeAckHandler(ackID: "rec-surv", isExactlyOnce: true))

    let receiptTask = Task {
      await defaultEOD.registerBatch(
        [
          .init(ackID: "rec-perm", leaseTracker: permTracker),
          .init(ackID: "rec-surv", leaseTracker: survTracker),
        ],
        isExactlyOnce: true
      )
    }
    await clock.waitUntilWaiters(atLeast: 1)
    clock.advance(by: .seconds(5))
    let surviving = await receiptTask.value
    #expect(surviving.map(\.ackID) == ["rec-surv"])
    #expect(permReleased.withLock { $0 })
    let recCalls = server.capturedCalls.filter {
      $0.method == PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
    }
    #expect(recCalls.count == 2)
    #expect(recCalls[0].modAckRequest?.ackDeadlineSeconds == 60)
    #expect(recCalls[1].modAckRequest?.ackIds == ["rec-surv"])

    // EOD-03b: mixed Acknowledge batch [ok, perm, trans] -> ok & perm resolve on call 1, only trans retries.
    server.setAckHandler { req, _, _ in
      if req.ackIds.contains("eod-perm") || req.ackIds.count == 3 {
        throw FakePubSubServer.makeEODError(
          code: .invalidArgument,
          metadata: [
            "eod-perm": "PERMANENT_FAILURE_INVALID_ACK_ID",
            "eod-trans": "TRANSIENT_FAILURE_UNORDERED_ACK_ID",
          ]
        )
      }
    }

    let preMixedAckCount = server.capturedCalls.count
    let tOk = Task {
      try await defaultEOD.makeAckHandler(ackID: "eod-ok", isExactlyOnce: true).ackWithResult()
    }
    let tPerm = Task {
      try await defaultEOD.makeAckHandler(ackID: "eod-perm", isExactlyOnce: true).ackWithResult()
    }
    let tTrans = Task {
      try await defaultEOD.makeAckHandler(ackID: "eod-trans", isExactlyOnce: true).ackWithResult()
    }

    // Advance past 5ms coalesce window, then past retry backoff for eod-trans.
    try await Task.sleep(for: .milliseconds(25))
    clock.advance(by: .milliseconds(10))
    #expect(try await tOk.value == AckResult(status: .success))
    await #expect {
      _ = try await tPerm.value
    } throws: { error in
      if case PubSubError.settlementFailed(let ackErr) = error {
        return ackErr.status == .invalidAckID
      }
      return false
    }
    await clock.waitUntilWaiters(atLeast: 1)
    clock.advance(by: .seconds(5))
    #expect(try await tTrans.value == AckResult(status: .success))

    let mixedAckCalls = server.capturedCalls[preMixedAckCount...].filter {
      $0.method == PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
    }
    #expect(mixedAckCalls.count == 2)
    #expect(Set(mixedAckCalls[0].ackRequest?.ackIds ?? []) == ["eod-ok", "eod-perm", "eod-trans"])
    #expect(mixedAckCalls[1].ackRequest?.ackIds == ["eod-trans"])

    survTracker.markSettled()
    await defaultEOD.bulkNackRemainingAndClose(timeout: .seconds(1))
    await customEOD.bulkNackRemainingAndClose(timeout: .seconds(1))
    await pool.shutdown()
  }

  @Test func eodPendingAckExtendsLeaseUntilAckCompletesAndStopsAfterward() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try self.makePool(endpoint: server.endpoint)
    defer { Task { await pool.shutdown() } }

    let clock = ControllableClock()
    let options = SubscribeOptions().with {
      $0.minAckExtension = .seconds(10)
      $0.maxAckExtension = .seconds(60)
      $0.maxExtension = .seconds(8)
      $0.request.retryThrottler = CircuitBreaker()
    }
    let manager = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: options,
      pool: pool,
      clock: clock
    )

    let ackAttempts = TestBox(0)
    let ackGate = AsyncStream<Void>.makeStream()
    defer { ackGate.continuation.finish() }
    server.setAckHandler { _, _, _ in
      let attempt = ackAttempts.withLock { v -> Int in
        v += 1
        return v
      }
      if attempt == 1 {
        throw FakePubSubServer.makeEODError(
          code: .invalidArgument,
          metadata: ["pend-ack-1": "TRANSIENT_FAILURE_UNORDERED_ACK_ID"]
        )
      }
      var it = ackGate.stream.makeAsyncIterator()
      _ = await it.next()
    }

    let handler = manager.makeAckHandler(ackID: "pend-ack-1", isExactlyOnce: true)
    let tracker = LeaseTracker(handler: handler)
    let registered = await manager.registerBatch(
      [.init(ackID: "pend-ack-1", leaseTracker: tracker)],
      isExactlyOnce: true
    )
    #expect(registered.count == 1)

    let preAckCallCount = server.capturedCalls.count
    tracker.markSettled()
    let ackTask = Task { try await handler.ackWithResult() }
    try await Task.sleep(for: .milliseconds(25))
    clock.advance(by: .milliseconds(10))

    // Wait for Acknowledge attempt #1 failure, advance past backoff into stalled attempt #2,
    // then advance past 8s maxExtension & 5s renewal interval to verify pending EOD ack renewal.
    await server.waitForCalls(
      atLeast: 1,
      method: PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
    )
    await clock.waitUntilWaiters(atLeast: 2)
    clock.advance(by: .seconds(9))
    await server.waitForCall { calls in
      calls[preAckCallCount...].contains {
        $0.method == PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
          && $0.modAckRequest?.ackDeadlineSeconds == 10
          && ($0.modAckRequest?.ackIds.contains("pend-ack-1") ?? false)
      }
    }
    // Verify adaptive/non-adaptive static branch (`enableAdaptiveAckExtension = false`).
    let staticMgr = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.streamAckDeadline = .seconds(45)
        $0.minAckExtension = .seconds(10)
        $0.maxAckExtension = .seconds(600)
        $0.enableAdaptiveAckExtension = false
      },
      pool: pool,
      clock: clock
    )
    #expect(staticMgr.initialExtensionSeconds(isExactlyOnce: false) == 45)
    await staticMgr.bulkNackRemainingAndClose(timeout: .seconds(1))

    ackGate.continuation.yield()
    ackGate.continuation.finish()
    #expect(try await ackTask.value == AckResult(status: .success))
    #expect(manager.activeLeaseCount == 0)

    await manager.bulkNackRemainingAndClose(timeout: .seconds(1))
  }

  @Test func duplicateAckIDsInEODAndDroppedPullCoalescedSettlementDoNotDrop() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try self.makePool(endpoint: server.endpoint)
    defer { Task { await pool.shutdown() } }

    let manager = LeaseManager(
      subscription: self.subscription,
      subscribeOptions: SubscribeOptions().with {
        $0.request.retryThrottler = CircuitBreaker()
      },
      pool: pool,
      clock: SystemPubSubClock()
    )
    let h1 = manager.makeAckHandler(ackID: "dup-eod", isExactlyOnce: true)
    let h2 = manager.makeAckHandler(ackID: "dup-eod", isExactlyOnce: true)
    let t1 = LeaseTracker(handler: h1)
    let t2 = LeaseTracker(handler: h2)
    let survived = await manager.registerBatch(
      [
        .init(ackID: "dup-eod", leaseTracker: t1),
        .init(ackID: "dup-eod", leaseTracker: t2),
      ],
      isExactlyOnce: true
    )
    #expect(survived.count == 2)
    let recCall = try #require(
      server.capturedCalls.last {
        $0.method == PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
      }
    )
    #expect(recCall.modAckRequest?.ackIds == ["dup-eod"])
    t1.markSettled()
    t2.markSettled()
    await manager.bulkNackRemainingAndClose(timeout: .seconds(1))

    // Dropping a PullResult/LeaseManager immediately after fire-and-forget ack() still flushes RPC.
    do {
      let shortLivedManager = LeaseManager(
        subscription: self.subscription,
        subscribeOptions: SubscribeOptions().with {
          $0.maxExtension = .zero
          $0.request.retryThrottler = CircuitBreaker()
        },
        pool: pool,
        clock: SystemPubSubClock()
      )
      shortLivedManager.ack(ackID: "ephemeral-ack-1", isExactlyOnce: false, options: .init())
    }
    await server.waitForCall { calls in
      calls.contains { $0.ackRequest?.ackIds.contains("ephemeral-ack-1") ?? false }
    }
  }
}
