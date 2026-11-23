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
import InMemoryLogging
import Logging
import Synchronization
import SwiftProtobuf
import Testing
import _GoogleCloudPubSubProtos
@testable import GoogleCloudPubSub

@Suite struct BlockingPublisherTests {
  @Test func publishesImmediatelyAndResolvesShortAndCrossProjectTopics() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try BlockingPublisherClient(
      BlockingPublisherClientOptions().with {
        $0.projectID = "default-proj"
        $0.subchannelCount = 2
        $0.client.endpoint = server.endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      })

    let res1 = try await client.publish(
      Message(data: Data("hello".utf8), attributes: ["k": "v"]),
      topic: "short-topic"
    )
    #expect(res1 == PublishResult(messageID: "fake-msg-1"))

    let res2 = try await client.publish(
      Message(),
      topic: "projects/other-proj/topics/cross-topic",
      options: BlockingPublishOptions().with {
        $0.request.headers = HTTPHeaders([("x-custom", "blk")])
      }
    )
    #expect(res2 == PublishResult(messageID: "fake-msg-2"))

    let calls = server.capturedCalls
    #expect(calls.count == 2)
    #expect(calls[0].publishRequest?.topic == "projects/default-proj/topics/short-topic")
    #expect(calls[0].publishRequest?.messages.count == 1)
    #expect(calls[0].publishRequest?.messages[0].data == Data("hello".utf8))
    #expect(calls[0].publishRequest?.messages[0].attributes == ["k": "v"])
    #expect(calls[1].publishRequest?.topic == "projects/other-proj/topics/cross-topic")
    #expect(calls[1].publishRequest?.messages[0].data == Data())
    #expect(
      calls[1].metadata["x-goog-request-params"]
        == ["topic=projects%2Fother-proj%2Ftopics%2Fcross-topic"])
    #expect(calls[1].metadata["x-custom"] == ["blk"])
  }

  @Test func appliesCompressionAboveThresholdAndAllowsPerCallOverride() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let client = try BlockingPublisherClient(
      BlockingPublisherClientOptions().with {
        $0.projectID = "p"
        $0.compression = CompressionOptions().with {
          $0.isEnabled = true
          $0.bytesThreshold = 200
        }
        $0.client.endpoint = server.endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      })

    _ = try await client.publish(Message(data: Data(repeating: 0x41, count: 100)), topic: "t")
    _ = try await client.publish(Message(data: Data(repeating: 0x42, count: 300)), topic: "t")
    _ = try await client.publish(
      Message(data: Data(repeating: 0x43, count: 300)),
      topic: "t",
      options: BlockingPublishOptions().with {
        $0.compression = CompressionOptions().with { $0.isEnabled = false }
      }
    )

    let calls = server.capturedCalls
    #expect(calls.count == 3)
    #expect(calls[0].metadata["grpc-encoding"] == nil)
    #expect(calls[1].metadata["grpc-encoding"] == ["gzip"])
    #expect(calls[2].metadata["grpc-encoding"] == nil)
  }

  @Test func retriesTransientFailuresAndStopsOnPermanentOrOversizedErrors() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    final class AttemptCounter: Sendable {
      let value = Atomic(0)
    }
    let attempts = AttemptCounter()
    server.setPublishHandler { req, _, _, _ in
      let attempt = attempts.value.add(1, ordering: .relaxed).newValue
      if attempt == 1 {
        throw RPCError(code: .unavailable, message: "transient unavailable")
      }
      return Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = req.messages.enumerated().map { idx, _ in "ok-\(idx)" }
      }
    }

    let clock = ControllableClock()
    let client = try BlockingPublisherClient(
      BlockingPublisherClientOptions().with {
        $0.projectID = "p"
        $0.client.endpoint = server.endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      },
      clock: clock,
      environment: [:]
    )

    let task = Task {
      try await client.publish(
        Message(data: Data("retry-me".utf8)),
        topic: "t",
        options: BlockingPublishOptions().with {
          $0.request.backoffPolicy = try? ExponentialBackoff(
            initialDelay: .seconds(2),
            maximumDelay: .seconds(4),
            scaling: 2.0
          )
          $0.request.retryThrottler = CircuitBreaker()
        }
      )
    }
    await clock.waitUntilWaiters(atLeast: 1)
    #expect(attempts.value.load(ordering: .relaxed) == 1)
    clock.advance(by: .seconds(10))
    let retried = try await task.value
    #expect(retried == PublishResult(messageID: "ok-0"))
    #expect(attempts.value.load(ordering: .relaxed) == 2)

    // Oversized > 10MB rejects locally with zero wire RPCs.
    let preCount = server.capturedCalls.count
    await #expect {
      _ = try await client.publish(
        Message(data: Data(repeating: 0x01, count: 10_000_001)),
        topic: "t"
      )
    } throws: { error in
      if case PubSubError.messageTooLarge = error { return true }
      return false
    }
    #expect(server.capturedCalls.count == preCount)

    // Mismatched message_ids count fails cleanly with zero retries.
    server.setPublishHandler { _, _, _, _ in
      Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = []
      }
    }
    let preMismatchCount = server.capturedCalls.count
    await #expect {
      _ = try await client.publish(Message(data: Data("bad-resp".utf8)), topic: "t")
    } throws: { error in
      if case PubSubError.mismatchedMessageIDCount(let expected, let received) = error {
        return expected == 1 && received == 0
      }
      return false
    }
    #expect(server.capturedCalls.count == preMismatchCount + 1)

    // Permanent gRPC error logs once and does not retry.
    let logHandler = InMemoryLogHandler()
    var logger = Logger(label: "blk-test") { _ in logHandler }
    logger.logLevel = .debug
    let loggedClient = try BlockingPublisherClient(
      BlockingPublisherClientOptions().with {
        $0.projectID = "p"
        $0.client.endpoint = server.endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
        $0.client.logger = logger
      })
    server.setPublishHandler { _, _, _, _ in
      throw RPCError(code: .permissionDenied, message: "denied")
    }
    do {
      _ = try await loggedClient.publish(Message(data: Data("denied".utf8)), topic: "t")
      Issue.record("Expected RequestError.service")
    } catch let error as RequestError {
      guard case .service(let svc) = error else {
        Issue.record("Unexpected error: \(error)")
        return
      }
      #expect(svc.code == .permissionDenied)
    }
    #expect(logHandler.entries.count == 2)  // 1 debug attempt + 1 terminal error
    #expect(logHandler.entries[1].level == .error)
    #expect(logHandler.entries[1].metadata["rpc.method"] == "google.pubsub.v1.Publisher/Publish")

    await loggedClient.shutdown()
    await client.shutdown()
  }
}
