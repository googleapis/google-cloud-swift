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
import GoogleRpc
import GoogleWKT
import InMemoryLogging
import Logging
import _GoogleCloudPubSubProtos
import SwiftProtobuf
import Testing
@testable import GoogleCloudPubSub

@Suite struct SubscriberTests {
  private let subscription = "projects/p/subscriptions/sub-a"

  private func makeClient(
    endpoint: String,
    projectID: String? = "p",
    logger: Logger? = nil,
    clock: any PubSubClock = SystemPubSubClock()
  ) throws -> SubscriberClient {
    let options = SubscriberClientOptions().with {
      $0.projectID = projectID
      $0.subchannelCount = 1
      $0.client.endpoint = endpoint
      $0.client.credentials = try? Credentials(configuration: .anonymous)
      if let logger {
        $0.client.logger = logger
      }
      $0.defaultSubscribeOptions.request.retryThrottler = CircuitBreaker()
      $0.defaultPullOptions.request.retryThrottler = CircuitBreaker()
    }
    return try SubscriberClient(options, clock: clock, environment: [:])
  }

  private func makeProtoMessage(
    id: String,
    ackID: String,
    payload: String
  ) -> Google_Pubsub_V1_ReceivedMessage {
    Google_Pubsub_V1_ReceivedMessage.with {
      $0.ackID = ackID
      $0.message = Google_Pubsub_V1_PubsubMessage.with {
        $0.messageID = id
        $0.data = Data(payload.utf8)
      }
    }
  }

  private func waitForSleeps(
    _ clock: ControllableClock,
    minSleepsStarted: Int,
    minActiveWaiters: Int = 1
  ) async {
    for _ in 0..<100 {
      if clock.sleepsStarted >= minSleepsStarted
        && clock.pendingWaiterCount >= minActiveWaiters
      {
        return
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test func frameZeroMetadataPreservesClientIDAndFlowControl() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let clock = ControllableClock()
    let client = try self.makeClient(endpoint: server.endpoint, clock: clock)
    defer { Task { await client.shutdown() } }

    let options = SubscribeOptions().with {
      $0.streamCount = 1
      $0.maxOutstandingMessages = 42
      $0.maxOutstandingBytes = 65_536
      $0.streamAckDeadline = .seconds(900)
      $0.enablePerStreamFlowControl = true
      $0.request.retryPolicy = PubSubRetryPolicy.defaultPublishPolicy
      $0.request.retryThrottler = CircuitBreaker()
    }
    let stream = try client.subscribe(subscription: "sub-a", options: options)

    let session1 = await server.waitForStreamingSession(index: 1)
    await session1.waitForFrames(atLeast: 1)

    let frame0 = session1.frames[0]
    #expect(frame0.subscription == self.subscription)
    #expect(frame0.streamAckDeadlineSeconds == 600)
    #expect(frame0.protocolVersion == 1)
    #expect(frame0.maxOutstandingMessages == 42)
    #expect(frame0.maxOutstandingBytes == 65_536)
    #expect(!frame0.clientID.isEmpty)
    #expect(
      session1.metadata["x-goog-request-params"]?.contains(
        "subscription=projects%2Fp%2Fsubscriptions%2Fsub-a") == true
    )

    // Close stream 1 with transient Unavailable -> reconnects reusing exact clientID.
    await self.waitForSleeps(clock, minSleepsStarted: 1, minActiveWaiters: 1)
    let sleepsBeforeClose = clock.sleepsStarted
    session1.close(error: RPCError(code: .unavailable, message: "transient bounce"))
    await self.waitForSleeps(
      clock,
      minSleepsStarted: sleepsBeforeClose + 1,
      minActiveWaiters: 1
    )
    clock.advance(by: .seconds(2))

    let session2 = await server.waitForStreamingSession(index: 2)
    await session2.waitForFrames(atLeast: 1)
    #expect(session2.frames[0].clientID == frame0.clientID)

    _ = try await stream.stop(
      options: SubscriberShutdownOptions().with {
        $0.behavior = .nackImmediately
      }
    )

    // Verify Frame 0 populates clientID and flow-control limits cleanly.
    let noFlowStream = try client.subscribe(
      subscription: self.subscription,
      options: SubscribeOptions().with {
        $0.enablePerStreamFlowControl = false
        $0.clientID = "custom-client-id"
      }
    )
    let session3 = await server.waitForStreamingSession(index: 3)
    await session3.waitForFrames(atLeast: 1)
    #expect(session3.frames[0].clientID == "custom-client-id")
    #expect(session3.frames[0].maxOutstandingMessages == 1_000)
    #expect(session3.frames[0].maxOutstandingBytes == 104_857_600)
    _ = try await noFlowStream.stop()
  }

  @Test func keepalivePongPreventsRecycleUnderFlowControlAndTimeoutRecycles() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let clock = ControllableClock()
    let client = try self.makeClient(endpoint: server.endpoint, clock: clock)
    defer { Task { await client.shutdown() } }

    let stream = try #require(
      try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with {
          $0.maxOutstandingMessages = 1
          $0.keepalivePingInterval = .seconds(10)
          $0.keepalivePongTimeout = .seconds(5)
          $0.request.retryThrottler = CircuitBreaker()
        }
      ) as? MessageStream
    )

    let session1 = await server.waitForStreamingSession(index: 1)
    await session1.waitForFrames(atLeast: 1)
    // Wait until keepaliveTask arms its sleep on ControllableClock.
    await clock.waitUntilWaiters(atLeast: 1)

    // Send m1 and m2; maxOutstandingMessages=1 pauses delivery of m2 while m1 is unsettled.
    session1.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "1", ackID: "ack-1", payload: "one"),
          self.makeProtoMessage(id: "2", ackID: "ack-2", payload: "two"),
        ]
      }
    )

    var iter = stream.makeAsyncIterator()
    let raw1 = try await iter.next()
    let msg1 = try #require(raw1)
    #expect(msg1.message.messageID == "1")

    // Fire keepalive ping while m2 is flow-control paused (`PULL-03b`).
    clock.advance(by: .seconds(10))
    await session1.waitForFrames(atLeast: 2)
    let pingFrame1 = session1.frames[1]
    #expect(pingFrame1 == Google_Pubsub_V1_StreamingPullRequest())

    // Wait for watchdog pong timer + next ping sleep before sending server pong.
    await clock.waitUntilWaiters(atLeast: 2)
    session1.sendResponse(Google_Pubsub_V1_StreamingPullResponse())
    try await Task.sleep(for: .milliseconds(25))

    // Advance past keepalivePongTimeout (5s) -> canceled watchdog must NOT recycle stream.
    clock.advance(by: .seconds(5))
    try await Task.sleep(for: .milliseconds(25))
    #expect(server.streamingSessions.count == 1)

    // Acknowledge m1 -> flow gate releases m2 immediately.
    _ = msg1.ack()
    let raw2 = try await iter.next()
    let msg2 = try #require(raw2)
    #expect(msg2.message.messageID == "2")
    _ = msg2.ack()

    // Now trigger another keepalive ping WITHOUT a server pong (`PULL-03`).
    await clock.waitUntilWaiters(atLeast: 1)
    clock.advance(by: .seconds(5))  // 5 + 5 = 10s next ping
    await session1.waitForFrames(atLeast: 3)
    #expect(session1.frames[2] == Google_Pubsub_V1_StreamingPullRequest())

    // Watchdog timer (5s) + next ping timer (10s) armed -> advance 5s to fire PongTimeoutError.
    await clock.waitUntilWaiters(atLeast: 2)
    clock.advance(by: .seconds(5))

    let session2 = await server.waitForStreamingSession(index: 2)
    await session2.waitForFrames(atLeast: 1)
    #expect(session2.frames[0].clientID == session1.frames[0].clientID)

    session2.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "3", ackID: "ack-3", payload: "three")
        ]
      }
    )
    let raw3 = try await iter.next()
    let msg3 = try #require(raw3)
    #expect(msg3.message.messageID == "3")
    _ = msg3.ack()

    _ = try await stream.stop()
  }

  @Test func recoversTransientFailureAndLogsO4OnTerminalPermissionDenied() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let inMemory = InMemoryLogHandler()
    let logger = Logger(label: "pubsub-sub-test") { _ in inMemory }
    let clock = ControllableClock()
    let client = try self.makeClient(endpoint: server.endpoint, logger: logger, clock: clock)
    defer { Task { await client.shutdown() } }

    let stream = try #require(
      try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with {
          $0.request.retryThrottler = CircuitBreaker()
        }
      ) as? MessageStream
    )

    // Session 1 closes with transient Unavailable.
    let session1 = await server.waitForStreamingSession(index: 1)
    await session1.waitForFrames(atLeast: 1)
    await self.waitForSleeps(clock, minSleepsStarted: 1, minActiveWaiters: 1)
    let sleepsBeforeClose = clock.sleepsStarted
    session1.close(error: RPCError(code: .unavailable, message: "temporary drop"))

    await self.waitForSleeps(
      clock,
      minSleepsStarted: sleepsBeforeClose + 1,
      minActiveWaiters: 1
    )
    clock.advance(by: .seconds(2))

    // Session 2 delivers 1 message, then fails permanently with PermissionDenied.
    let session2 = await server.waitForStreamingSession(index: 2)
    await session2.waitForFrames(atLeast: 1)
    session2.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [self.makeProtoMessage(id: "m1", ackID: "a1", payload: "ok")]
      }
    )

    var iter = stream.makeAsyncIterator()
    let rawFirst = try await iter.next()
    let first = try #require(rawFirst)
    #expect(first.message.messageID == "m1")
    _ = first.ack()

    session2.close(error: RPCError(code: .permissionDenied, message: "denied"))

    do {
      _ = try await iter.next()
      Issue.record("Expected terminal PermissionDenied error from stream")
    } catch let reqErr as GoogleGax.RequestError {
      if case .service(let svcErr) = reqErr {
        #expect(svcErr.code == .permissionDenied)
      } else {
        Issue.record("Expected .service error, got \(reqErr)")
      }
    }

    // Must not open a 3rd session after terminal error.
    try await Task.sleep(for: .milliseconds(25))
    #expect(server.streamingSessions.count == 2)

    let errorLogs = inMemory.entries.filter { $0.level == .error }
    #expect(!errorLogs.isEmpty)
    let o4 = try #require(errorLogs.last)
    #expect(o4.metadata["gcp.artifact.id"] == "google-cloud-pubsub")
    #expect(o4.metadata["rpc.method"] == "google.pubsub.v1.Subscriber/StreamingPull")
    #expect(o4.metadata["rpc.grpc.status_code"] == "PERMISSION_DENIED")

    _ = try await stream.stop()
  }

  @Test func perStreamVsSharedFlowControlAndIdleOversizedException() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try self.makeClient(endpoint: server.endpoint)
    defer { Task { await client.shutdown() } }

    // Case 1: per-stream flow control (2 streams x 1 msg each = 2 admitted concurrently).
    let perStream = try #require(
      try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with {
          $0.streamCount = 2
          $0.maxOutstandingMessages = 1
          $0.maxOutstandingBytes = 10_000
          $0.enablePerStreamFlowControl = true
        }
      ) as? MessageStream
    )

    let s1 = await server.waitForStreamingSession(index: 1)
    let s2 = await server.waitForStreamingSession(index: 2)
    await s1.waitForFrames(atLeast: 1)
    await s2.waitForFrames(atLeast: 1)

    s1.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [self.makeProtoMessage(id: "s1", ackID: "ack-s1", payload: "a")]
      }
    )
    s2.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [self.makeProtoMessage(id: "s2", ackID: "ack-s2", payload: "b")]
      }
    )

    var it1 = perStream.makeAsyncIterator()
    let rawM1 = try await it1.next()
    let rawM2 = try await it1.next()
    let m1 = try #require(rawM1)
    let m2 = try #require(rawM2)
    #expect(Set([m1.message.messageID, m2.message.messageID]) == Set(["s1", "s2"]))
    _ = m1.ack()
    _ = m2.ack()
    _ = try await perStream.stop()

    // Case 2: shared flow control (`enablePerStreamFlowControl = false`) across 2 streams
    // restricts combined unsettled count to 1, and permits idle oversized payload.
    let sharedStream = try client.subscribe(
      subscription: self.subscription,
      options: SubscribeOptions().with {
        $0.streamCount = 2
        $0.maxOutstandingMessages = 1
        $0.maxOutstandingBytes = 10
        $0.enablePerStreamFlowControl = false
      }
    )
    let s3 = await server.waitForStreamingSession(index: 3)
    let s4 = await server.waitForStreamingSession(index: 4)
    await s3.waitForFrames(atLeast: 1)
    await s4.waitForFrames(atLeast: 1)

    let pipe = AsyncThrowingStream.makeStream(of: ReceivedMessage.self)
    let pumpTask = Task {
      do {
        for try await msg in sharedStream {
          pipe.continuation.yield(msg)
        }
        pipe.continuation.finish()
      } catch {
        pipe.continuation.finish(throwing: error)
      }
    }
    var it2 = pipe.stream.makeAsyncIterator()

    // Single 32-byte payload arrives on idle gate (> maxOutstandingBytes = 10) -> admitted.
    s3.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(
            id: "big",
            ackID: "ack-big",
            payload: String(repeating: "x", count: 32)
          )
        ]
      }
    )
    let rawBig = try await it2.next()
    let big = try #require(rawBig)
    #expect(big.message.messageID == "big")

    // Send on s4 while big is unsettled -> must block until big is acked.
    let deliveredAfterHold = TestBox(false)
    let (secondWaitStream, secondWaitCont) = AsyncThrowingStream.makeStream(
      of: ReceivedMessage.self)
    let waitForSecondTask = Task {
      if let next = try await it2.next() {
        deliveredAfterHold.withLock { $0 = true }
        secondWaitCont.yield(next)
      }
      secondWaitCont.finish()
    }
    s4.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [self.makeProtoMessage(id: "next", ackID: "ack-next", payload: "y")]
      }
    )
    try await Task.sleep(for: .milliseconds(30))
    #expect(!deliveredAfterHold.withLock { $0 })

    _ = big.ack()
    var nextIter = secondWaitStream.makeAsyncIterator()
    let rawNext = try await nextIter.next()
    let next = try #require(rawNext)
    #expect(next.message.messageID == "next")
    _ = next.ack()
    _ = try await waitForSecondTask.value
    _ = try await sharedStream.stop()
    await pumpTask.value
  }

  @Test func dynamicExactlyOnceToggleReceiptGatingAndDropAutoNack() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let modAckCallCount = TestBox(0)
    server.setModAckHandler { req, _, _ in
      let count = modAckCallCount.withLock { count -> Int in
        count += 1
        return count
      }
      if req.ackDeadlineSeconds > 0 && req.ackIds.contains("eod-retry") && count <= 2 {
        throw RPCError(code: .unavailable, message: "transient eod receipt")
      }
      if req.ackDeadlineSeconds > 0 && req.ackIds.contains("eod-perm") {
        throw FakePubSubServer.makeEODError(
          code: .permissionDenied,
          metadata: ["eod-perm": "PERMANENT_FAILURE_INVALID_ACK_ID"]
        )
      }
    }

    let clock = ControllableClock()
    let client = try self.makeClient(endpoint: server.endpoint, clock: clock)
    defer { Task { await client.shutdown() } }

    let stream = try #require(
      try client.subscribe(subscription: self.subscription) as? MessageStream
    )
    let session = await server.waitForStreamingSession(index: 1)
    await session.waitForFrames(atLeast: 1)

    // Phase 1: EOD disabled -> drop unsettled msg1 should auto-nack with ModAck(0).
    session.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.subscriptionProperties = Google_Pubsub_V1_StreamingPullResponse.SubscriptionProperties
          .with {
            $0.exactlyOnceDeliveryEnabled = false
          }
        $0.receivedMessages = [
          self.makeProtoMessage(id: "p1", ackID: "at-least-once", payload: "1")
        ]
      }
    )

    var iter = stream.makeAsyncIterator()
    do {
      let raw1 = try await iter.next()
      let msg1 = try #require(raw1)
      #expect(!msg1.isExactlyOnce)
    }
    try await Task.sleep(for: .milliseconds(10))
    clock.advance(by: .milliseconds(20))
    await server.waitForCalls(
      atLeast: 2,
      method: PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
    )
    let nacks = server.capturedCalls.compactMap(\.modAckRequest).filter {
      $0.ackDeadlineSeconds == 0 && $0.ackIds.contains("at-least-once")
    }
    #expect(!nacks.isEmpty)

    // Phase 2: EOD enabled -> transient error retried, permanent ack dropped, valid ack delivered.
    session.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.subscriptionProperties = Google_Pubsub_V1_StreamingPullResponse.SubscriptionProperties
          .with {
            $0.exactlyOnceDeliveryEnabled = true
          }
        $0.receivedMessages = [
          self.makeProtoMessage(id: "p2-perm", ackID: "eod-perm", payload: "drop"),
          self.makeProtoMessage(id: "p2-retry", ackID: "eod-retry", payload: "ok"),
        ]
      }
    )
    // Pump ControllableClock briefly to unblock EOD receipt ModAck retry backoff.
    for _ in 0..<8 {
      try await Task.sleep(for: .milliseconds(10))
      clock.advance(by: .seconds(2))
    }
    let raw2 = try await iter.next()
    let msg2 = try #require(raw2)
    #expect(msg2.message.messageID == "p2-retry")
    #expect(msg2.isExactlyOnce)
    _ = msg2.ack()

    // Phase 3: EOD toggled back to false -> non-EOD message yielded immediately.
    session.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.subscriptionProperties = Google_Pubsub_V1_StreamingPullResponse.SubscriptionProperties
          .with {
            $0.exactlyOnceDeliveryEnabled = false
          }
        $0.receivedMessages = [self.makeProtoMessage(id: "p3", ackID: "non-eod-2", payload: "3")]
      }
    )
    let raw3 = try await iter.next()
    let msg3 = try #require(raw3)
    #expect(msg3.message.messageID == "p3")
    #expect(!msg3.isExactlyOnce)
    _ = msg3.ack()

    _ = try await stream.stop()
  }

  @Test func shutdownWaitForProcessingTimeoutAndNackImmediately() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let clock = ControllableClock()
    let client = try self.makeClient(endpoint: server.endpoint, clock: clock)
    defer { Task { await client.shutdown() } }

    // 1. WaitForProcessing with finite timeout bulk-nacks unsettled after deadline.
    let stream1 = try #require(
      try client.subscribe(subscription: self.subscription) as? MessageStream
    )
    let s1 = await server.waitForStreamingSession(index: 1)
    await s1.waitForFrames(atLeast: 1)
    s1.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [self.makeProtoMessage(id: "w1", ackID: "wait-1", payload: "hold")]
      }
    )

    var iter1 = stream1.makeAsyncIterator()
    let rawHeld = try await iter1.next()
    let heldMsg = try #require(rawHeld)

    // Let initial ModAck(10s) and its 5s renewal sleep settle before starting stopTask.
    await server.waitForCalls(
      atLeast: 1,
      method: PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod
    )
    await self.waitForSleeps(clock, minSleepsStarted: 2, minActiveWaiters: 2)

    let sleepsBeforeStop = clock.sleepsStarted
    let stopTask = Task {
      try await stream1.stop(
        options: SubscriberShutdownOptions().with {
          $0.behavior = .waitForProcessing
          $0.timeout = .seconds(5)
        }
      )
    }
    await self.waitForSleeps(
      clock,
      minSleepsStarted: sleepsBeforeStop + 1,
      minActiveWaiters: 2
    )
    clock.advance(by: .seconds(5))
    _ = try await stopTask.value

    // Calling stop again is idempotent.
    _ = try await stream1.stop()
    let eof1 = try await iter1.next()
    #expect(eof1 == nil)
    #expect(
      server.capturedCalls.contains { call in
        guard let req = call.modAckRequest else { return false }
        return req.ackDeadlineSeconds == 0 && req.ackIds.contains("wait-1")
      }
    )
    _ = heldMsg

    // 2. NackImmediately cancels gated/un-dispatched and active leases in one shot.
    let stream2 = try #require(
      try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with {
          $0.maxOutstandingMessages = 1
        }
      ) as? MessageStream
    )
    let s2 = await server.waitForStreamingSession(index: 2)
    await s2.waitForFrames(atLeast: 1)
    s2.sendResponse(
      Google_Pubsub_V1_StreamingPullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "i1", ackID: "imm-1", payload: "a"),
          self.makeProtoMessage(id: "i2", ackID: "imm-2", payload: "b"),
        ]
      }
    )
    var iter2 = stream2.makeAsyncIterator()
    let rawImm1 = try await iter2.next()
    let imm1 = try #require(rawImm1)

    _ = try await stream2.stop(
      options: SubscriberShutdownOptions().with {
        $0.behavior = .nackImmediately
      }
    )
    let eof2 = try await iter2.next()
    #expect(eof2 == nil)
    let zeroNackIDs = Set(
      server.capturedCalls
        .compactMap(\.modAckRequest)
        .filter { $0.ackDeadlineSeconds == 0 }
        .flatMap(\.ackIds)
    )
    #expect(zeroNackIDs.contains("imm-1"))
    #expect(zeroNackIDs.contains("imm-2"))
    _ = imm1
  }

  @Test func managedUnaryPullValidationAndDropLifecycle() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try self.makeClient(endpoint: server.endpoint)
    defer { Task { await client.shutdown() } }

    // Validation failures on subscribe & pull.
    #expect(throws: PubSubError.self) {
      _ = try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with { $0.streamCount = 0 }
      )
    }
    #expect(throws: PubSubError.self) {
      _ = try client.subscribe(
        subscription: self.subscription,
        options: SubscribeOptions().with { $0.keepalivePingInterval = .zero }
      )
    }
    await #expect(throws: PubSubError.self) {
      _ = try await client.pull(
        subscription: self.subscription,
        options: PullOptions().with { $0.maxMessages = 0 }
      )
    }
    let noProjectClient = try self.makeClient(endpoint: server.endpoint, projectID: nil)
    defer { Task { await noProjectClient.shutdown() } }
    await #expect(throws: PubSubError.self) {
      _ = try await noProjectClient.pull(subscription: "short-sub")
    }

    // Empty PullResponse.
    server.setPullHandler { _, _, _ in Google_Pubsub_V1_PullResponse() }
    let empty = try await client.pull(subscription: "sub-a")
    #expect(empty.messages.isEmpty)

    // Populated PullResponse enrolls messages in lease management; dropping unsettled msg2 nacks.
    server.setPullHandler { req, _, _ in
      #expect(req.subscription == self.subscription)
      #expect(req.maxMessages == 7)
      #expect(req.returnImmediately)
      return Google_Pubsub_V1_PullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "u1", ackID: "u-ack-1", payload: "alpha"),
          self.makeProtoMessage(id: "u2", ackID: "u-ack-2", payload: "beta"),
        ]
      }
    }

    do {
      let result = try await client.pull(
        subscription: "sub-a",
        options: PullOptions().with {
          $0.maxMessages = 7
          $0.returnImmediately = true
        }
      )
      #expect(result.messages.count == 2)
      let ackResult = try await result.messages[0].ackWithResult()
      #expect(ackResult.status == .success)
      // result.messages[1] ("u-ack-2") is intentionally dropped unsettled when leaving scope.
    }

    await server.waitForCalls(
      atLeast: 1,
      method: PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
    )
    await server.waitForCall { calls in
      calls.contains { call in
        guard let req = call.modAckRequest else { return false }
        return req.ackDeadlineSeconds == 0 && req.ackIds.contains("u-ack-2")
      }
    }

    let ackedIDs = server.capturedCalls.compactMap(\.ackRequest).flatMap(\.ackIds)
    #expect(ackedIDs.contains("u-ack-1"))

    let autoNacked = server.capturedCalls.compactMap(\.modAckRequest).filter {
      $0.ackDeadlineSeconds == 0 && $0.ackIds.contains("u-ack-2")
    }
    #expect(!autoNacked.isEmpty)
  }

  @Test func nonEODLeaseRenewalFiresWithSystemClock() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try self.makeClient(endpoint: server.endpoint)
    defer { Task { await client.shutdown() } }

    server.setPullHandler { _, _, _ in
      Google_Pubsub_V1_PullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "sys-1", ackID: "sys-ack-1", payload: "hello")
        ]
      }
    }

    let result = try await client.pull(
      subscription: "sub-a",
      options: PullOptions().with {
        $0.maxMessages = 1
        $0.returnImmediately = true
      }
    )
    #expect(result.messages.count == 1)

    await server.waitForCall { calls in
      calls.contains { call in
        guard let req = call.modAckRequest else { return false }
        return req.ackDeadlineSeconds >= 10 && req.ackIds.contains("sys-ack-1")
      }
    }

    let ackResult = try await result.messages[0].ackWithResult()
    #expect(ackResult.status == .success)
  }

  @Test func messageStreamNextCancellationAndAckOptionsForwarding() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let streamGate = AsyncStream<Void>.makeStream()
    server.setStreamingPullHandler { session in
      await session.waitForFrames(atLeast: 1)
      var it = streamGate.stream.makeAsyncIterator()
      _ = await it.next()
      session.close()
    }

    let client = try self.makeClient(endpoint: server.endpoint)
    defer { Task { await client.shutdown() } }

    let stream = try client.subscribe(subscription: "sub-a")
    let nextTask = Task {
      var iter = stream.makeAsyncIterator()
      return try await iter.next()
    }
    try await Task.sleep(for: .milliseconds(25))
    nextTask.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await nextTask.value
    }
    streamGate.continuation.finish()
    _ = try await stream.stop()

    server.setPullHandler { _, _, _ in
      Google_Pubsub_V1_PullResponse.with {
        $0.receivedMessages = [
          self.makeProtoMessage(id: "opt-1", ackID: "opt-ack-1", payload: "payload")
        ]
      }
    }
    let pullResult = try await client.pull(
      subscription: "sub-a",
      options: PullOptions().with {
        $0.maxMessages = 1
        $0.returnImmediately = true
      }
    )
    let ackOpts = AckOptions().with {
      $0.request.headers = HTTPHeaders([("x-ack-custom", "ack-hdr-1")])
    }
    _ = try await pullResult.messages[0].ackWithResult(options: ackOpts)
    let ackCall = try #require(
      server.capturedCalls.last {
        $0.method == PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod
      }
    )
    #expect(ackCall.metadata["x-ack-custom"] == ["ack-hdr-1"])
  }
}
