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
import InMemoryLogging
import Logging
import _GoogleCloudPubSubProtos
import SwiftProtobuf
import Testing
@testable import GoogleCloudPubSub

@Suite struct PublisherTests {
  private func baseClientOptions(
    endpoint: String,
    projectID: String = "proj",
    logger: Logger? = nil
  ) -> PublisherClientOptions {
    PublisherClientOptions().with {
      $0.projectID = projectID
      $0.subchannelCount = 2
      $0.client.endpoint = endpoint
      $0.client.credentials = try? Credentials(configuration: .anonymous)
      if let logger {
        $0.client.logger = logger
      }
      $0.defaultTopicOptions.request.retryThrottler = CircuitBreaker()
    }
  }

  @Test func batchCountByteAndFirstMessageDelayTriggers() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let clock = ControllableClock()
    let topicOptions = TopicPublisherOptions().with {
      $0.batching.countThreshold = 3
      $0.batching.byteThreshold = 500
      $0.batching.delayThreshold = .milliseconds(100)
      $0.request.retryThrottler = CircuitBreaker()
    }
    let publisher = try Publisher(
      topic: "batched-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint),
      options: topicOptions,
      clock: clock,
      environment: [:]
    )

    // 1) Count trigger at 3 messages.
    let h1 = try await publisher.startPublish(Message(data: Data("a".utf8)))
    let h2 = try await publisher.startPublish(Message(data: Data("b".utf8)))
    try await Task.sleep(for: .milliseconds(20))
    #expect(server.capturedCalls.isEmpty)

    let h3 = try await publisher.startPublish(Message(data: Data("c".utf8)))
    await server.waitForCalls(atLeast: 1)
    #expect(try await h1.result() == PublishResult(messageID: "fake-msg-1"))
    #expect(try await h2.result() == PublishResult(messageID: "fake-msg-2"))
    #expect(try await h3.result() == PublishResult(messageID: "fake-msg-3"))

    // 2) First-message-only timer (PUB-05): advance 60ms after 1st, add 2nd, still open; +50ms fires!
    let h4 = try await publisher.startPublish(Message(data: Data("t1".utf8)))
    await clock.waitUntilWaiters(atLeast: 1)
    clock.advance(by: .milliseconds(60))
    let h5 = try await publisher.startPublish(Message(data: Data("t2".utf8)))
    try await Task.sleep(for: .milliseconds(20))
    #expect(server.capturedCalls.count == 1)

    clock.advance(by: .milliseconds(50))
    await server.waitForCalls(atLeast: 2)
    #expect(try await h4.result() == PublishResult(messageID: "fake-msg-4"))
    #expect(try await h5.result() == PublishResult(messageID: "fake-msg-5"))
    #expect(server.capturedCalls[1].publishRequest?.messages.count == 2)

    // 3) Byte threshold splits before exceeding 500 bytes (PUB-04 / PUB-06).
    let payload260 = Data(repeating: 0x41, count: 260)
    let hb1 = try await publisher.startPublish(Message(data: payload260))
    let hb2 = try await publisher.startPublish(Message(data: payload260))
    await server.waitForCalls(atLeast: 3)
    #expect(try await hb1.result() == PublishResult(messageID: "fake-msg-6"))
    _ = try await publisher.flush()
    #expect(try await hb2.result() == PublishResult(messageID: "fake-msg-7"))
    #expect(server.capturedCalls.count == 4)
    #expect(server.capturedCalls[2].publishRequest?.messages.count == 1)
    #expect(server.capturedCalls[3].publishRequest?.messages.count == 1)

    _ = try await publisher.shutdown()
  }

  @Test func clampsProtocolLimitsSplitsOver10MBAndValidatesResponseIDs() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let clock = ControllableClock()
    let publisher = try Publisher(
      topic: "limit-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint),
      options: TopicPublisherOptions().with {
        $0.batching.countThreshold = 2000
        $0.batching.byteThreshold = 32_000_000
        $0.batching.delayThreshold = .seconds(30)
        $0.request.retryThrottler = CircuitBreaker()
      },
      clock: clock,
      environment: [:]
    )

    // Oversized > 10MB rejects locally with zero wire RPCs (PUB-06b).
    await #expect {
      _ = try await publisher.startPublish(Message(data: Data(repeating: 0x58, count: 10_000_001)))
    } throws: { error in
      if case PubSubError.messageTooLarge = error { return true }
      return false
    }
    #expect(server.capturedCalls.isEmpty)

    // Two 6MB messages split into 2 RPCs instead of exceeding 10MB request limit (PUB-06).
    let sixMB = Data(repeating: 0x42, count: 6_000_000)
    let hA = try await publisher.startPublish(Message(data: sixMB))
    let hB = try await publisher.startPublish(Message(data: sixMB))
    await server.waitForCalls(atLeast: 1)
    _ = try await publisher.flush()
    _ = try await hA.result()
    _ = try await hB.result()
    #expect(server.capturedCalls.count == 2)
    #expect(server.capturedCalls[0].publishRequest?.messages.count == 1)
    #expect(server.capturedCalls[1].publishRequest?.messages.count == 1)

    // Count limit clamped to 1,000 when configured as 2,000 (PUB-03).
    var handles: [PublishHandle] = []
    handles.reserveCapacity(1_005)
    for idx in 0..<1_005 {
      handles.append(try await publisher.startPublish(Message(data: Data("m\(idx)".utf8))))
    }
    await server.waitForCalls(atLeast: 3)
    #expect(server.capturedCalls[2].publishRequest?.messages.count == 1_000)
    _ = try await publisher.flush()
    for handle in handles {
      _ = try await handle.result()
    }
    #expect(server.capturedCalls[3].publishRequest?.messages.count == 5)

    // Mismatched server message ID count fails cleanly without retry (PUB-10).
    let preMismatchCount = server.capturedCalls.count
    server.setPublishHandler { _, _, _, _ in
      Google_Pubsub_V1_PublishResponse.with { $0.messageIds = [] }
    }
    let badHandle = try await publisher.startPublish(Message(data: Data("mismatch".utf8)))
    _ = try await publisher.flush()
    await #expect {
      _ = try await badHandle.result()
    } throws: { error in
      if case PubSubError.mismatchedMessageIDCount(expected: 1, received: 0) = error {
        return true
      }
      return false
    }
    #expect(server.capturedCalls.count == preMismatchCount + 1)

    _ = try await publisher.shutdown()
  }

  @Test func compressionAndFlushAndShutdownBehavior() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try PublisherClient(
      self.baseClientOptions(endpoint: server.endpoint).with {
        $0.defaultTopicOptions.batching.countThreshold = 10
        $0.defaultTopicOptions.batching.delayThreshold = .seconds(30)
        $0.defaultTopicOptions.compression = CompressionOptions().with {
          $0.isEnabled = true
          $0.bytesThreshold = 200
        }
      })

    let publisher = try client.publisher(topic: "cmp-topic")

    // Small flush remains uncompressed.
    let smallHandle = try await publisher.startPublish(
      Message(data: Data(repeating: 0x61, count: 40)))
    _ = try await publisher.flush()
    _ = try await smallHandle.result()
    #expect(server.capturedCalls[0].metadata["grpc-encoding"] == nil)

    // Large batch triggers gzip compression (CMP-01).
    let largeHandle = try await publisher.startPublish(
      Message(data: Data(repeating: 0x62, count: 400)))
    _ = try await publisher.flush()
    _ = try await largeHandle.result()
    #expect(server.capturedCalls[1].metadata["grpc-encoding"] == ["gzip"])

    // PublisherClient shutdown drains child publishers & shuts down pool (PUB-08).
    let preShutHandle = try await publisher.startPublish(Message(data: Data("last".utf8)))
    _ = try await client.shutdown()
    #expect(try await preShutHandle.result() == PublishResult(messageID: "fake-msg-3"))

    await #expect {
      _ = try await publisher.startPublish(Message(data: Data("rejected".utf8)))
    } throws: { error in
      if case PubSubError.publisherShutDown = error { return true }
      return false
    }
    #expect {
      _ = try client.publisher(topic: "another")
    } throws: { error in
      if case PubSubError.publisherShutDown = error { return true }
      return false
    }
  }

  @Test func orderingKeysSerializeFIFOCorkAndResumeOnFailures() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let k1Gate = AsyncStream.makeStream(of: Void.self)
    let inGateCont = TestBox<CheckedContinuation<Void, Never>?>(nil)
    let gateEntered = TestBox(false)

    server.setPublishHandler { req, _, _, _ in
      let payload = String(decoding: req.messages.first?.data ?? Data(), as: UTF8.self)
      if payload == "k1-hold" {
        gateEntered.withLock { $0 = true }
        let cont = inGateCont.withLock { c -> CheckedContinuation<Void, Never>? in
          let out = c
          c = nil
          return out
        }
        cont?.resume()
        var iter = k1Gate.stream.makeAsyncIterator()
        _ = await iter.next()
      } else if payload == "k1-fail" {
        throw RPCError(code: .invalidArgument, message: "bad msg")
      }
      return Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = req.messages.map { "ok-\(String(decoding: $0.data, as: UTF8.self))" }
      }
    }

    let logHandler = InMemoryLogHandler()
    var logger = Logger(label: "pub-order") { _ in logHandler }
    logger.logLevel = .error

    let publisher = try Publisher(
      topic: "ordered-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint, logger: logger),
      options: TopicPublisherOptions().with {
        $0.batching.countThreshold = 1
        $0.batching.delayThreshold = .seconds(5)
        $0.request.retryThrottler = CircuitBreaker()
      },
      clock: ControllableClock(),
      environment: [:]
    )

    let hHold = try await publisher.startPublish(
      Message(data: Data("k1-hold".utf8), orderingKey: "k1"))
    await withCheckedContinuation { cont in
      let alreadyEntered = gateEntered.withLock { entered -> Bool in
        if entered { return true }
        inGateCont.withLock { $0 = cont }
        return false
      }
      if alreadyEntered {
        cont.resume()
      }
    }
    let hQueued = try await publisher.startPublish(
      Message(data: Data("k1-queued".utf8), orderingKey: "k1"))
    let hk2 = try await publisher.startPublish(Message(data: Data("k2-1".utf8), orderingKey: "k2"))

    #expect(try await hk2.result() == PublishResult(messageID: "ok-k2-1"))
    try await Task.sleep(for: .milliseconds(25))
    // While k1-hold is at the server, k1-queued has NOT been dispatched yet.
    #expect(
      !server.capturedCalls.contains(where: {
        $0.publishRequest?.messages.first?.data == Data("k1-queued".utf8)
      }))

    k1Gate.continuation.yield()
    k1Gate.continuation.finish()
    #expect(try await hHold.result() == PublishResult(messageID: "ok-k1-hold"))
    #expect(try await hQueued.result() == PublishResult(messageID: "ok-k1-queued"))

    // Permanent failure corks key, fails queued items, logs O4, and resumes only on resumePublishing (PORD-03).
    let hFail = try await publisher.startPublish(
      Message(data: Data("k1-fail".utf8), orderingKey: "k1"))
    await #expect {
      _ = try await hFail.result()
    } throws: { error in
      if case RequestError.service = error { return true }
      return false
    }
    #expect(logHandler.entries.contains { $0.level == .error })

    await #expect {
      _ = try await publisher.startPublish(Message(data: Data("k1-paused".utf8), orderingKey: "k1"))
    } throws: { error in
      if case PubSubError.orderingKeyPaused(orderingKey: "k1") = error { return true }
      return false
    }

    // k2 stays healthy while k1 is paused.
    let hk2Second = try await publisher.startPublish(
      Message(data: Data("k2-2".utf8), orderingKey: "k2"))
    #expect(try await hk2Second.result() == PublishResult(messageID: "ok-k2-2"))

    _ = try await publisher.resumePublishing(orderingKey: "k1")
    let hRecovered = try await publisher.startPublish(
      Message(data: Data("k1-ok".utf8), orderingKey: "k1"))
    #expect(try await hRecovered.result() == PublishResult(messageID: "ok-k1-ok"))

    _ = try await publisher.shutdown()
  }

  @Test func signalErrorOnKeyedPublishPreservesInFlightAndPausesKey() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let gate = AsyncStream.makeStream(of: Void.self)
    server.setPublishHandler { req, _, _, _ in
      if req.messages.first?.data == Data("k1-1".utf8) {
        var iter = gate.stream.makeAsyncIterator()
        _ = await iter.next()
      }
      return Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = req.messages.map { "id-\(String(decoding: $0.data, as: UTF8.self))" }
      }
    }

    let publisher = try Publisher(
      topic: "pfc03b-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint),
      options: TopicPublisherOptions().with {
        $0.batching.countThreshold = 1
        $0.flowControl.maxPendingMessages = 1
        $0.flowControl.limitExceededBehavior = .signalError
      },
      clock: ControllableClock(),
      environment: [:]
    )

    let h1 = try await publisher.startPublish(Message(data: Data("k1-1".utf8), orderingKey: "k1"))
    await server.waitForCalls(atLeast: 1)

    // Overflow with k1-2 under signalError throws flowControlLimitExceeded AND pauses "k1" (PFC-03b).
    await #expect {
      _ = try await publisher.startPublish(Message(data: Data("k1-2".utf8), orderingKey: "k1"))
    } throws: { error in
      if case PubSubError.flowControlLimitExceeded(.messageCount(pending: 2, limit: 1)) = error {
        return true
      }
      return false
    }

    // Release in-flight k1-1 -> succeeds cleanly!
    gate.continuation.yield()
    gate.continuation.finish()
    #expect(try await h1.result() == PublishResult(messageID: "id-k1-1"))

    // Subsequent k1-3 is still paused until resumePublishing("k1").
    await #expect {
      _ = try await publisher.startPublish(Message(data: Data("k1-3".utf8), orderingKey: "k1"))
    } throws: { error in
      if case PubSubError.orderingKeyPaused(orderingKey: "k1") = error { return true }
      return false
    }

    _ = try await publisher.resumePublishing(orderingKey: "k1")
    let h4 = try await publisher.startPublish(Message(data: Data("k1-4".utf8), orderingKey: "k1"))
    #expect(try await h4.result() == PublishResult(messageID: "id-k1-4"))

    _ = try await publisher.shutdown()
  }

  @Test func hedgingColdStartRefillCancellationAndOrderingSuppression() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let primaryGate = AsyncStream.makeStream(of: Void.self)
    let keyedGate = AsyncStream.makeStream(of: Void.self)
    let attemptCounter = TestBox(0)

    server.setPublishHandler { req, metadata, _, _ in
      let body = String(decoding: req.messages.first?.data ?? Data(), as: UTF8.self)
      if body == "hedge-race" {
        let idx = attemptCounter.withLock { v -> Int in
          v += 1
          return v
        }
        if idx == 1 {
          var iter = primaryGate.stream.makeAsyncIterator()
          _ = await iter.next()
          throw RPCError(code: .unavailable, message: "primary failed after hedge")
        }
        return Google_Pubsub_V1_PublishResponse.with { $0.messageIds = ["hedge-winner"] }
      }
      if body == "slow-keyed" {
        var iter = keyedGate.stream.makeAsyncIterator()
        _ = await iter.next()
      }
      let _ = metadata
      return Google_Pubsub_V1_PublishResponse.with { $0.messageIds = ["ok-\(body)"] }
    }

    let clock = ControllableClock()
    let publisher = try Publisher(
      topic: "hedge-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint),
      options: TopicPublisherOptions().with {
        $0.batching.countThreshold = 1
        $0.hedging = HedgingOptions().with {
          $0.isEnabled = true
          $0.delay = .milliseconds(200)
          $0.maxTokens = 2
          $0.refillRatio = 0.2
        }
        $0.request.retryThrottler = CircuitBreaker()
      },
      clock: clock,
      environment: [:]
    )

    // 5 successful RPCs refill bucket from 0 -> 1,000 milli-tokens (1.0 token, HDG-01).
    for i in 0..<5 {
      let h = try await publisher.startPublish(Message(data: Data("warm-\(i)".utf8)))
      _ = try await h.result()
    }

    // Primary stalls -> advance 200ms -> hedge #1 fires with attempt=1 telemetry & wins (HDG-02).
    let preRaceCount = server.capturedCalls.count
    let raceTask = Task {
      let h = try await publisher.startPublish(Message(data: Data("hedge-race".utf8)))
      return try await h.result()
    }
    await server.waitForCalls(atLeast: preRaceCount + 1)
    await clock.waitUntilWaiters(atLeast: 1)
    clock.advance(by: .milliseconds(200))

    let raceResult = try await raceTask.value
    #expect(raceResult == PublishResult(messageID: "hedge-winner"))
    primaryGate.continuation.yield()

    let raceCalls = Array(server.capturedCalls[preRaceCount...])
    #expect(raceCalls.count == 2)
    let t0B64 = try #require(raceCalls[0].metadata["x-goog-pubsub-client-telemetry"]?.first)
    let t1B64 = try #require(raceCalls[1].metadata["x-goog-pubsub-client-telemetry"]?.first)
    let t0 = try Google_Pubsub_V1_PubsubClientTelemetry(
      serializedBytes: Data(base64Encoded: t0B64)!)
    let t1 = try Google_Pubsub_V1_PubsubClientTelemetry(
      serializedBytes: Data(base64Encoded: t1B64)!)
    #expect(t0.publishOperation.hedgedAttemptCount == 0)
    #expect(t1.publishOperation.hedgedAttemptCount == 1)
    #expect(t0.publishOperation.hasPublishStartTime)

    // Keyed message with hedging enabled suppresses concurrent hedges even with refilled tokens (HDG-04).
    for i in 0..<5 {
      let h = try await publisher.startPublish(Message(data: Data("refill-\(i)".utf8)))
      _ = try await h.result()
    }
    let preKeyedCount = server.capturedCalls.count
    let keyedTask = Task {
      let h = try await publisher.startPublish(
        Message(data: Data("slow-keyed".utf8), orderingKey: "k"))
      return try await h.result()
    }
    await server.waitForCalls(atLeast: preKeyedCount + 1)
    clock.advance(by: .milliseconds(500))
    try await Task.sleep(for: .milliseconds(25))
    #expect(server.capturedCalls.count == preKeyedCount + 1)
    keyedGate.continuation.yield()
    keyedGate.continuation.finish()
    primaryGate.continuation.finish()
    #expect(try await keyedTask.value == PublishResult(messageID: "ok-slow-keyed"))
    let tkB64 = try #require(
      server.capturedCalls[preKeyedCount].metadata["x-goog-pubsub-client-telemetry"]?.first)
    let tk = try Google_Pubsub_V1_PubsubClientTelemetry(
      serializedBytes: Data(base64Encoded: tkB64)!)
    #expect(tk.publishOperation.hedgedAttemptCount == 0)

    _ = try await publisher.shutdown()
  }

  @Test func optionsPropagationAndCancellationSafety() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let gate = AsyncStream<Void>.makeStream()
    server.setPublishHandler { req, _, _, _ in
      var iter = gate.stream.makeAsyncIterator()
      _ = await iter.next()
      return Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = (0..<req.messages.count).map { "m-\($0)" }
      }
    }

    let publisher = try Publisher(
      topic: "cancel-topic",
      clientOptions: self.baseClientOptions(endpoint: server.endpoint),
      options: TopicPublisherOptions().with {
        $0.batching.countThreshold = 1
        $0.request.retryThrottler = CircuitBreaker()
      }
    )

    let customOpts = PublishOptions().with {
      $0.request.headers = HTTPHeaders([("x-per-msg-opt", "val-1")])
    }
    let handle = try await publisher.startPublish(
      Message(data: Data("blocked".utf8)),
      options: customOpts
    )
    await server.waitForCalls(atLeast: 1)
    #expect(server.capturedCalls[0].metadata["x-per-msg-opt"] == ["val-1"])

    let resultTask = Task { try await handle.result() }
    try await Task.sleep(for: .milliseconds(15))
    resultTask.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await resultTask.value
    }

    let flushTask = Task { try await publisher.flush() }
    try await Task.sleep(for: .milliseconds(15))
    flushTask.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await flushTask.value
    }

    gate.continuation.yield()
    gate.continuation.finish()
    #expect(try await handle.result() == PublishResult(messageID: "m-0"))
    _ = try await publisher.shutdown()
  }
}
