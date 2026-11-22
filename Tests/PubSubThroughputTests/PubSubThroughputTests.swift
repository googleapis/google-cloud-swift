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
import GoogleCloudPubSub
import PubSubThroughput
import Synchronization
import Testing

private final class AckCounter: Sendable {
  let value = Atomic(0)
}

private actor MockPubSubCounters {
  var published: Int = 0
  var flushed: Int = 0
  var acked: Int = 0

  func recordPublish() -> String {
    self.published += 1
    return "id-\(self.published)"
  }

  func recordFlush() {
    self.flushed += 1
  }

  func recordAck() {
    self.acked += 1
  }
}

private struct MockPublisher: Clients.PublisherProtocol {
  let topic: String
  let counters: MockPubSubCounters

  func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle {
    let counters = self.counters
    return PublishHandle {
      let id = await counters.recordPublish()
      return PublishResult(messageID: id)
    }
  }

  func flush(options: FlushOptions) async throws -> FlushResult {
    await self.counters.recordFlush()
    return FlushResult()
  }

  func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    ShutdownResult()
  }
}

private struct MockAckHandler: AckHandlerProtocol {
  let ackCount: AckCounter

  func ack(options: AckOptions) -> AckQueuedResult {
    self.ackCount.value.add(1, ordering: .relaxed)
    return AckQueuedResult()
  }
}

private struct MockSubscriber: Clients.SubscriberProtocol {
  let messages: [Message]
  let ackCount = AckCounter()

  func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    let items = self.messages.map { msg in
      ReceivedMessage(message: msg, ackHandler: MockAckHandler(ackCount: self.ackCount))
    }
    return MessageStream(messages: items)
  }
}

@Suite struct PubSubThroughputTests {
  @Test func throughputMetricsDecimalMegabytes() {
    let metrics = ThroughputMetrics.compute(
      mode: "publish",
      totalMessages: 500_000,
      totalBytes: 500_000_000,
      elapsedSeconds: 2.0,
      latenciesMillis: [1.0, 2.0, 3.0, 4.0, 10.0]
    )
    #expect(metrics.messagesPerSecond == 250_000.0)
    #expect(metrics.megabytesPerSecond == 250.0)
    #expect(metrics.p50LatencyMillis == 3.0)
    #expect(metrics.p99LatencyMillis == 10.0)
  }

  @Test func cliArgumentParsingAndValidation() throws {
    let pubCmd = try PubSubThroughput.parse([
      "--mode", "publish",
      "--project", "my-proj",
      "--topic", "my-topic",
      "--payload-size", "1024",
      "--batch-size", "200",
      "--batch-bytes", "2097152",
      "--channels", "8",
      "--ordering-keys", "4",
      "--total-messages", "1000",
      "--json",
    ])
    #expect(pubCmd.mode == .publish)
    #expect(pubCmd.projectID == "my-proj")
    #expect(pubCmd.topic == "my-topic")
    #expect(pubCmd.payloadSize == 1_024)
    #expect(pubCmd.channels == 8)
    #expect(pubCmd.orderingKeys == 4)
    #expect(pubCmd.json)
    #expect(pubCmd.makeTopicPublisherOptions().batching.countThreshold == 200)

    let subCmd = try PubSubThroughput.parse([
      "--mode", "subscribe",
      "--project", "my-proj",
      "--subscription", "my-sub",
      "--streams", "16",
      "--endurance",
      "--duration-seconds", "30",
    ])
    #expect(subCmd.mode == .subscribe)
    #expect(subCmd.makeSubscribeOptions().streamCount == 16)

    #expect(throws: (any Error).self) {
      _ = try PubSubThroughput.parse(["--mode", "publish", "--project", "p"])
    }
    #expect(throws: (any Error).self) {
      _ = try PubSubThroughput.parse([
        "--mode", "subscribe", "--project", "p", "--subscription", "s", "--streams", "0",
      ])
    }
  }

  @Test func publishAndSubscribeBenchmarkKernels() async throws {
    let counters = MockPubSubCounters()
    let mockPub = MockPublisher(topic: "projects/p/topics/t", counters: counters)
    let pubMetrics = try await PubSubThroughput.runPublishBenchmark(
      publisher: mockPub,
      payloadSize: 512,
      totalMessages: 250,
      orderingKeys: 3,
      inflightLimit: 64
    )
    #expect(pubMetrics.totalMessages == 250)
    #expect(pubMetrics.totalBytes == 250 * 512)
    #expect(await counters.published == 250)
    #expect(await counters.flushed == 1)

    let sampleMessages = (0..<120).map { idx in
      Message(data: Data(repeating: UInt8(idx % 200), count: 256))
    }
    let mockSub = MockSubscriber(messages: sampleMessages)
    let subMetrics = try await PubSubThroughput.runSubscribeBenchmark(
      subscriber: mockSub,
      subscription: "projects/p/subscriptions/s",
      maxMessages: 100
    )
    #expect(subMetrics.totalMessages == 100)
    #expect(subMetrics.totalBytes == 100 * 256)
    #expect(mockSub.ackCount.value.load(ordering: .relaxed) == 100)
  }
}
