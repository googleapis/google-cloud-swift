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
import GoogleRpc
import Synchronization
import SwiftProtobuf
import Testing
import _GoogleCloudPubSubProtos
@_spi(GoogleCloudInternal) @testable import GoogleCloudPubSub

@Suite struct MessageAndOptionsTests {
  @Test func wireByteSizeMatchesProtobufSerialization() throws {
    let msg = Message(
      data: Data(repeating: 0xAB, count: 300),
      attributes: ["key1": "value1", "utf8-🔑": "val-🚀"],
      orderingKey: "order-123"
    )
    let encoded = try msg.toProto().serializedData()
    #expect(msg.estimatedWireByteSize() == encoded.count)
    try msg.validateForPublish()
  }

  @Test func emptyMessageIsValid() throws {
    let empty = Message()
    let encoded = try empty.toProto().serializedData()
    #expect(empty.estimatedWireByteSize() == encoded.count)
    #expect(encoded.count == 0)
    try empty.validateForPublish()
  }

  @Test func rejectsMessageOver10MBWithoutRPC() {
    let oversized = Message(data: Data(repeating: 0x01, count: 10_000_001))
    #expect {
      try oversized.validateForPublish()
    } throws: { error in
      guard case PubSubError.messageTooLarge(let sizeBytes, let limitBytes) = error else {
        return false
      }
      return sizeBytes > limitBytes && limitBytes == 10_000_000
    }
  }

  @Test func rejectsInvalidUTF8RawBytes() {
    let invalid = Data([0x61, 0xC5, 0x7A])
    #expect {
      _ = try Message._decodeValidatedUTF8(invalid, label: "key")
    } throws: { error in
      if case PubSubError.invalidUTF8Attribute = error {
        return true
      }
      return false
    }
  }

  @Test func pubSubErrorDescriptionsAreNonEmpty() {
    let ackErr = AckError(
      status: .invalidAckID,
      message: "expired",
      underlyingError: RequestError.service(ServiceError(code: .invalidArgument, message: "bad"))
    )
    let allErrors: [PubSubError] = [
      .publisherShutDown,
      .orderingKeyPaused(orderingKey: "k"),
      .messageTooLarge(sizeBytes: 11, limitBytes: 10),
      .invalidUTF8Attribute(description: "bad utf8"),
      .flowControlLimitExceeded(.messageCount(pending: 5, limit: 4)),
      .flowControlLimitExceeded(.byteCount(pendingBytes: 100, limitBytes: 50)),
      .emptyProjectID(resource: "t"),
      .mismatchedMessageIDCount(expected: 2, received: 1),
      .settlementFailed(ackErr),
      .invalidConfiguration(description: "bad delay"),
    ]
    for err in allErrors {
      #expect(!err.description.isEmpty)
      #expect(err.debugDescription.hasPrefix("PubSubError."))
      #expect(!err.debugDescription.hasPrefix("PubSubError.\(err.description):"))
    }
  }

  @Test func defaultTopicOptionsAreInheritedViaClientAndStandalonePublisher() throws {
    let clientOptions = PublisherClientOptions().with {
      $0.projectID = "proj"
      $0.defaultTopicOptions.batching.countThreshold = 42
    }
    let client: any Clients.PublisherClientProtocol = try PublisherClient(clientOptions)
    let created = try client.publisher(topic: "my-topic")
    let concrete = try #require(created as? Publisher)
    #expect(concrete.topic == "projects/proj/topics/my-topic")
    #expect(concrete.options.batching.countThreshold == 42)

    let standalone = try Publisher(topic: "solo-topic", clientOptions: clientOptions)
    #expect(standalone.options.batching.countThreshold == 42)
  }

  @Test func configurationValidationRejectsOutOfRangeValues() async throws {
    #expect(throws: PubSubError.self) {
      _ = try PublisherClient(PublisherClientOptions().with { $0.subchannelCount = 0 })
    }
    #expect(throws: PubSubError.self) {
      _ = try BlockingPublisherClient(
        BlockingPublisherClientOptions().with { $0.subchannelCount = 0 })
    }
    #expect(throws: PubSubError.self) {
      _ = try BlockingPublisherClient(
        BlockingPublisherClientOptions().with { $0.compression.bytesThreshold = -1 })
    }
    #expect(throws: PubSubError.self) {
      _ = try SubscriberClient(SubscriberClientOptions().with { $0.subchannelCount = 0 })
    }
    let sub = try SubscriberClient(SubscriberClientOptions().with { $0.projectID = "proj" })
    #expect(throws: PubSubError.self) {
      _ = try sub.subscribe(
        subscription: "s", options: SubscribeOptions().with { $0.streamCount = 0 })
    }
    #expect(throws: PubSubError.self) {
      _ = try sub.subscribe(
        subscription: "s",
        options: SubscribeOptions().with {
          $0.minAckExtension = .seconds(120)
          $0.maxAckExtension = .seconds(60)
        })
    }
    await #expect(throws: PubSubError.self) {
      _ = try await sub.pull(subscription: "s", options: PullOptions().with { $0.maxMessages = 0 })
    }
  }

  @Test func leaseTrackerReleasesPermitOnceOnExpiryThenSettle() {
    final class CounterHandler: AckHandlerProtocol, Sendable {
      let acks = Atomic(0)
      let nacks = Atomic(0)
      func ack(options: AckOptions) -> AckQueuedResult {
        self.acks.add(1, ordering: .relaxed)
        return AckQueuedResult()
      }
      func nack(options: NackOptions) -> NackQueuedResult {
        self.nacks.add(1, ordering: .relaxed)
        return NackQueuedResult()
      }
    }

    final class CounterBox: Sendable {
      let value = Atomic(0)
    }

    let handler = CounterHandler()
    let releaseCount = CounterBox()
    do {
      let tracker = LeaseTracker(
        handler: handler,
        onPermitRelease: { releaseCount.value.add(1, ordering: .relaxed) }
      )
      tracker.markExpired()
      tracker.markSettled()
    }
    #expect(releaseCount.value.load(ordering: .relaxed) == 1)
    #expect(handler.nacks.load(ordering: .relaxed) == 0)
  }

  @Test func pubSubRetryPolicyEvaluatesTransientAndLimits() throws {
    let policy = PubSubRetryPolicy().with {
      $0.maxAttempts = 3
      $0.timeLimit = .seconds(10)
    }
    let start = ContinuousClock.now
    let state1 = RetryState(start: start, attemptCount: 1)

    let transientRPC = RequestError.service(ServiceError(code: .unavailable, message: "retry"))
    let permanentRPC = RequestError.service(ServiceError(code: .permissionDenied, message: "nope"))
    let transientHTTP = RequestError.http(
      HTTPDetails(statusCode: 429, headers: .init(), payload: Data()))
    let permanentHTTP = RequestError.http(
      HTTPDetails(statusCode: 400, headers: .init(), payload: Data()))

    guard case .retry = policy.onError(state: state1, error: transientRPC) else {
      Issue.record("Expected unavailable RPC to retry")
      return
    }
    guard case .permanent = policy.onError(state: state1, error: permanentRPC) else {
      Issue.record("Expected permissionDenied RPC to fail permanently")
      return
    }
    guard case .retry = policy.onError(state: state1, error: transientHTTP) else {
      Issue.record("Expected 429 HTTP to retry")
      return
    }
    guard case .permanent = policy.onError(state: state1, error: permanentHTTP) else {
      Issue.record("Expected 400 HTTP to fail permanently")
      return
    }

    let stateMax = RetryState(start: start, attemptCount: 3)
    guard case .exhausted = policy.onError(state: stateMax, error: transientRPC) else {
      Issue.record("Expected maxAttempts exhaustion")
      return
    }
    guard case .exhausted = policy.onThrottle(state: stateMax, error: transientRPC) else {
      Issue.record("Expected onThrottle maxAttempts exhaustion")
      return
    }
    #expect(policy.remainingTime(state: state1) != nil)
    #expect(PubSubRetryPolicy().with { $0.timeLimit = nil }.remainingTime(state: state1) == nil)
  }
}
