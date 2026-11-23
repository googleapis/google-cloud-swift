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
import GRPCProtobuf
import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
import GoogleRpc
import InMemoryLogging
import Logging
import Synchronization
import SwiftProtobuf
import Testing
import _GoogleCloudPubSubProtos
@testable import GoogleCloudPubSub

@Suite struct ChannelPoolTests {
  @Test func subchannelCountLessThanOneThrowsInvalidConfiguration() {
    #expect {
      _ = try GRPCChannelPool(
        from: ClientOptions().with {
          $0.credentials = try? Credentials(configuration: .anonymous)
        },
        subchannelCount: 0,
        environment: [:]
      )
    } throws: { error in
      if case PubSubError.invalidConfiguration = error {
        return true
      }
      return false
    }
  }

  @Test func emulatorEnvironmentAndExplicitEndpointPrecedence() throws {
    let envPool = try GRPCChannelPool(
      from: ClientOptions(),
      subchannelCount: 2,
      environment: ["PUBSUB_EMULATOR_HOST": "127.0.0.1:8681"]
    )
    #expect(envPool.isEmulator == true)
    #expect(envPool.targetHost == "127.0.0.1")
    #expect(envPool.targetPort == 8681)
    #expect(envPool.subchannelCount == 2)

    let overridePool = try GRPCChannelPool(
      from: ClientOptions().with {
        $0.endpoint = "https://us-central1-pubsub.googleapis.com:8443"
        $0.credentials = try? Credentials(configuration: .anonymous)
      },
      subchannelCount: 1,
      environment: ["PUBSUB_EMULATOR_HOST": "127.0.0.1:8681"]
    )
    #expect(overridePool.isEmulator == false)
    #expect(overridePool.targetHost == "us-central1-pubsub.googleapis.com")
    #expect(overridePool.targetPort == 8443)
  }

  @Test func universeDomainResolvesHostWhenEndpointIsOmitted() throws {
    let pool = try GRPCChannelPool(
      from: ClientOptions().with {
        $0.universeDomain = "custom-universe.test"
        $0.credentials = try? Credentials(configuration: .anonymous)
      },
      subchannelCount: 1,
      environment: [:]
    )
    #expect(pool.universeDomain == "custom-universe.test")
    #expect(pool.targetHost == "pubsub.custom-universe.test")
    #expect(pool.targetPort == 443)
  }

  @Test func unaryAndStreamingSendHeadersCompressionAndLargePayloads() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    let pool = try GRPCChannelPool(
      from: ClientOptions().with {
        $0.endpoint = server.endpoint
        $0.quotaProject = "client-quota"
        $0.credentials = try? Credentials(configuration: .anonymous)
      },
      subchannelCount: 2,
      environment: [:]
    )

    var baseReqOpts = RequestOptions()
    baseReqOpts.headers = HTTPHeaders([
      ("x-custom-a", "from-base"),
      ("x-Override", "old"),
      ("x-goog-api-client", "evil-spoof"),
      ("authorization", "evil-auth"),
    ])
    var callReqOpts = RequestOptions()
    callReqOpts.quotaProject = "call-quota"
    callReqOpts.headers = HTTPHeaders([("x-override", "new")])
    let merged = GRPCChannelPool.mergeRequestOptions(base: baseReqOpts, override: callReqOpts)

    // Unary Publish with gzip compression + large payload support
    let topic = "projects/test-proj/topics/test-topic"
    let publishReq = Google_Pubsub_V1_PublishRequest.with {
      $0.topic = topic
      $0.messages = [
        Google_Pubsub_V1_PubsubMessage.with {
          $0.data = Data(repeating: 0x5A, count: 5_000_000)
        }
      ]
    }
    let publishResp: Google_Pubsub_V1_PublishResponse = try await pool.unary(
      descriptor: PubSubGRPCDescriptors.publish,
      request: publishReq,
      options: merged,
      routingParams: [_RoutingMatcher.format(key: "topic", value: topic)],
      extraHeaders: [(name: "x-goog-pubsub-client-telemetry", value: "Zm9v")],
      compression: .gzip
    )
    #expect(publishResp.messageIds == ["fake-msg-1"])

    let calls = server.capturedCalls
    #expect(calls.count == 1)
    let md = calls[0].metadata
    #expect(md["x-custom-a"] == ["from-base"])
    #expect(md["x-override"] == ["new"])
    #expect(md["x-goog-user-project"] == ["call-quota"])
    #expect(md["authorization"] == nil)
    #expect(md["x-goog-pubsub-client-telemetry"] == ["Zm9v"])
    #expect(md["grpc-encoding"] == ["gzip"])
    #expect(md["x-goog-request-params"] == ["topic=projects%2Ftest-proj%2Ftopics%2Ftest-topic"])
    let apiClient = md["x-goog-api-client"]?.first ?? ""
    #expect(apiClient.contains("gccl/\(PackageVersion.version)"))
    #expect(apiClient.contains("gl-swift/"))
    #expect(apiClient.contains("gax/"))

    // Bidirectional StreamingPull with custom headers, routing params, and > 4 MiB response (> 20 MiB cap check)
    let sub = "projects/test-proj/subscriptions/test-sub"
    server.setStreamingPullHandler { session in
      await session.waitForFrames(atLeast: 1)
      let bigMsg = Google_Pubsub_V1_ReceivedMessage.with {
        $0.ackID = "ack-big"
        $0.message = Google_Pubsub_V1_PubsubMessage.with {
          $0.messageID = "m-big"
          $0.data = Data(repeating: 0x33, count: 6_000_000)
        }
      }
      session.sendResponse(
        Google_Pubsub_V1_StreamingPullResponse.with {
          $0.receivedMessages = [bigMsg]
        })
      session.close()
    }

    let receivedPayloadSizes: [Int] = try await pool.bidirectionalStreaming(
      descriptor: PubSubGRPCDescriptors.streamingPull,
      subchannelIndex: 1,
      options: merged,
      routingParams: [_RoutingMatcher.format(key: "subscription", value: sub)],
      producer: { writer in
        try await writer.write(
          Google_Pubsub_V1_StreamingPullRequest.with {
            $0.subscription = sub
            $0.clientID = "cid-1"
            $0.streamAckDeadlineSeconds = 60
            $0.protocolVersion = 1
          })
      },
      onResponse: { (response: StreamingClientResponse<Google_Pubsub_V1_StreamingPullResponse>) in
        var sizes: [Int] = []
        for try await batch in response.messages {
          sizes.append(contentsOf: batch.receivedMessages.map { $0.message.data.count })
        }
        return sizes
      }
    )
    #expect(receivedPayloadSizes == [6_000_000])

    let session = await server.waitForStreamingSession(index: 1)
    #expect(session.metadata["x-custom-a"] == ["from-base"])
    #expect(session.metadata["x-override"] == ["new"])
    #expect(
      session.metadata["x-goog-request-params"]
        == ["subscription=projects%2Ftest-proj%2Fsubscriptions%2Ftest-sub"])

    await pool.shutdown()
  }

  @Test func errorInfoIsUnpackedAndStructuredLoggerMatchesContract() async throws {
    let server = try await FakePubSubServer.start()
    defer { Task { await server.stop() } }

    server.setAckHandler { _, _, _ in
      throw GoogleRPCStatus(
        code: .invalidArgument,
        message: "eod failure",
        details: [
          .errorInfo(
            reason: "EXACTLY_ONCE_ACKID_FAILURE",
            domain: "pubsub.googleapis.com",
            metadata: ["ack-1": "PERMANENT_FAILURE_INVALID_ACK_ID"]
          )
        ]
      )
    }

    let logHandler = InMemoryLogHandler()
    var logger = Logger(label: "pubsub-channel-pool-test") { _ in logHandler }
    logger.logLevel = .debug

    let pool = try GRPCChannelPool(
      from: ClientOptions().with {
        $0.endpoint = server.endpoint
        $0.credentials = try? Credentials(configuration: .anonymous)
        $0.logger = logger
      },
      subchannelCount: 1,
      environment: [:]
    )

    let sub = "projects/p/subscriptions/s"
    do {
      let _: Google_Protobuf_Empty = try await pool.unary(
        descriptor: PubSubGRPCDescriptors.acknowledge,
        request: Google_Pubsub_V1_AcknowledgeRequest.with {
          $0.subscription = sub
          $0.ackIds = ["ack-1"]
        },
        options: RequestOptions(),
        routingParams: [_RoutingMatcher.format(key: "subscription", value: sub)]
      )
      Issue.record("Expected RequestError.service")
    } catch let error as RequestError {
      pool.pubSubLogger.logTerminalError(
        error,
        method: .acknowledge,
        resource: sub,
        operation: "acknowledge"
      )
      guard case .service(let details) = error else {
        Issue.record("Expected .service error, got \(error)")
        return
      }
      #expect(details.code == .invalidArgument)
      guard case .errorInfo(let info)? = details.details.first else {
        Issue.record("Expected unpacked ErrorInfo detail")
        return
      }
      #expect(info.domain == "pubsub.googleapis.com")
      #expect(info.metadata == ["ack-1": "PERMANENT_FAILURE_INVALID_ACK_ID"])
    }

    let entries = logHandler.entries
    #expect(entries.count == 1)
    #expect(entries[0].metadata["gcp.artifact.id"] == "google-cloud-pubsub")
    #expect(entries[0].metadata["gcp.client.service"] == "pubsub")
    #expect(entries[0].metadata["gcp.client.version"] == .string(PackageVersion.version))
    #expect(entries[0].metadata["gcp.client.repo"] == "googleapis/google-cloud-swift")
    #expect(entries[0].metadata["gcp.resource.destination.id"] == "//pubsub.googleapis.com/\(sub)")
    #expect(entries[0].metadata["rpc.method"] == "google.pubsub.v1.Subscriber/Acknowledge")
    await pool.shutdown()
  }

  @Test func controllableClockAdvancesWaitersDeterministically() async throws {
    final class FlagBox: Sendable {
      let value = Atomic(false)
    }

    let clock = ControllableClock()
    let fired = FlagBox()
    let task = Task {
      try await clock.sleep(for: .seconds(30))
      fired.value.store(true, ordering: .releasing)
    }
    await clock.waitUntilWaiters(atLeast: 1)
    #expect(fired.value.load(ordering: .acquiring) == false)
    clock.advance(by: .seconds(15))
    #expect(clock.pendingWaiterCount == 1)
    clock.advance(by: .seconds(15))
    try await task.value
    #expect(fired.value.load(ordering: .acquiring) == true)
  }
}
