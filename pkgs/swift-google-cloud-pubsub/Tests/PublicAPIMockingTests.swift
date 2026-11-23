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
import GoogleAuth
import GoogleCloudPubSub
import GoogleGax
import GoogleRpc
import GoogleWKT
import Synchronization
import Testing

private final class LockedBox<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) {
    self.mutex = Mutex(value)
  }

  func withLock<R>(_ body: (inout sending Value) throws -> sending R) rethrows -> sending R {
    try self.mutex.withLock(body)
  }
}

private struct UnimplementedPublisherClient: Clients.PublisherClientProtocol {}
private struct UnimplementedPublisher: Clients.PublisherProtocol {}
private struct UnimplementedBlockingPublisher: Clients.BlockingPublisherProtocol {}
private struct UnimplementedSubscriber: Clients.SubscriberProtocol {}
private struct UnimplementedAckHandler: AckHandlerProtocol {}
private struct UnimplementedStream: MessageStreamProtocol {}

private final class RecordingAckHandler: AckHandlerProtocol, Sendable {
  struct Counts: Sendable, Equatable {
    var acks = 0
    var nacks = 0
    var ackWithResults = 0
    var nackWithResults = 0
  }

  private let counts = LockedBox(Counts())
  var snapshot: Counts { self.counts.withLock { $0 } }

  private let ackOutcome: Result<AckResult, any Error>

  init(ackOutcome: Result<AckResult, any Error> = .success(AckResult(status: .success))) {
    self.ackOutcome = ackOutcome
  }

  func ack(options: AckOptions) -> AckQueuedResult {
    self.counts.withLock { $0.acks += 1 }
    return AckQueuedResult()
  }

  func nack(options: NackOptions) -> NackQueuedResult {
    self.counts.withLock { $0.nacks += 1 }
    return NackQueuedResult()
  }

  func ackWithResult(options: AckOptions) async throws -> AckResult {
    self.counts.withLock { $0.ackWithResults += 1 }
    return try self.ackOutcome.get()
  }

  func nackWithResult(options: NackOptions) async throws -> AckResult {
    self.counts.withLock { $0.nackWithResults += 1 }
    return AckResult(status: .success)
  }
}

private final class ForwardingAckHandler: AckHandlerProtocol, Sendable {
  let inner: ReceivedMessage
  let forwarded = LockedBox(0)

  init(inner: ReceivedMessage) {
    self.inner = inner
  }

  func ack(options: AckOptions) -> AckQueuedResult {
    self.forwarded.withLock { $0 += 1 }
    return self.inner.ack(options: options)
  }

  func nack(options: NackOptions) -> NackQueuedResult {
    self.forwarded.withLock { $0 += 1 }
    return self.inner.nack(options: options)
  }

  func ackWithResult(options: AckOptions) async throws -> AckResult {
    self.forwarded.withLock { $0 += 1 }
    return try await self.inner.ackWithResult(options: options)
  }

  func nackWithResult(options: NackOptions) async throws -> AckResult {
    self.forwarded.withLock { $0 += 1 }
    return try await self.inner.nackWithResult(options: options)
  }
}

private final class MockPublisher: Clients.PublisherProtocol, Sendable {
  let topic: String
  let log = LockedBox<[String]>([])

  init(topic: String) {
    self.topic = topic
  }

  func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle {
    self.log.withLock { $0.append("startPublish:\(message.orderingKey)") }
    return PublishHandle(resolver: { PublishResult(messageID: "mock-\(message.data.count)") })
  }

  func flush(options: FlushOptions) async throws -> FlushResult {
    self.log.withLock { $0.append("flush") }
    return FlushResult()
  }

  func resumePublishing(
    orderingKey: String,
    options: ResumePublishingOptions
  ) async throws -> ResumePublishingResult {
    self.log.withLock { $0.append("resume:\(orderingKey)") }
    return ResumePublishingResult()
  }

  func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    self.log.withLock { $0.append("shutdown") }
    return ShutdownResult()
  }
}

private final class ForwardingPublisher: Clients.PublisherProtocol, Sendable {
  let inner: any Clients.PublisherProtocol
  let callCount = LockedBox(0)

  init(inner: any Clients.PublisherProtocol) {
    self.inner = inner
  }

  var topic: String { self.inner.topic }

  func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle {
    self.callCount.withLock { $0 += 1 }
    return try await self.inner.startPublish(message, options: options)
  }

  func flush(options: FlushOptions) async throws -> FlushResult {
    self.callCount.withLock { $0 += 1 }
    return try await self.inner.flush(options: options)
  }

  func resumePublishing(
    orderingKey: String,
    options: ResumePublishingOptions
  ) async throws -> ResumePublishingResult {
    self.callCount.withLock { $0 += 1 }
    return try await self.inner.resumePublishing(orderingKey: orderingKey, options: options)
  }

  func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    self.callCount.withLock { $0 += 1 }
    return try await self.inner.shutdown(options: options)
  }
}

private struct MockPublisherClient: Clients.PublisherClientProtocol {
  func publisher(topic: String, options: TopicPublisherOptions) throws
    -> any Clients.PublisherProtocol
  {
    MockPublisher(topic: topic)
  }

  func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult {
    ShutdownResult()
  }
}

private final class ForwardingPublisherClient: Clients.PublisherClientProtocol, Sendable {
  let inner: any Clients.PublisherClientProtocol
  let createdTopics = LockedBox<[String]>([])

  init(inner: any Clients.PublisherClientProtocol) {
    self.inner = inner
  }

  func publisher(topic: String, options: TopicPublisherOptions) throws
    -> any Clients.PublisherProtocol
  {
    self.createdTopics.withLock { $0.append(topic) }
    return ForwardingPublisher(inner: try self.inner.publisher(topic: topic, options: options))
  }

  func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult {
    try await self.inner.shutdown(options: options)
  }
}

private struct MockBlockingPublisher: Clients.BlockingPublisherProtocol {
  func publish(
    _ message: Message,
    topic: String,
    options: BlockingPublishOptions
  ) async throws -> PublishResult {
    PublishResult(messageID: "blk-\(topic)")
  }
}

private final class ForwardingBlockingPublisher: Clients.BlockingPublisherProtocol, Sendable {
  let inner: any Clients.BlockingPublisherProtocol
  let count = LockedBox(0)

  init(inner: any Clients.BlockingPublisherProtocol) {
    self.inner = inner
  }

  func publish(
    _ message: Message,
    topic: String,
    options: BlockingPublishOptions
  ) async throws -> PublishResult {
    self.count.withLock { $0 += 1 }
    return try await self.inner.publish(message, topic: topic, options: options)
  }
}

private final class MockSubscriber: Clients.SubscriberProtocol, Sendable {
  let handler: RecordingAckHandler
  let midStreamFailure: Bool

  init(handler: RecordingAckHandler, midStreamFailure: Bool = false) {
    self.handler = handler
    self.midStreamFailure = midStreamFailure
  }

  func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    let msg = Message(data: Data("payload".utf8), attributes: ["k": "v"], orderingKey: "k1")
      .with {
        $0.messageID = "m1"
        $0.deliveryAttempt = 2
        $0.publishTime = try? GoogleWKT.WKTTimestamp(seconds: 10, nanos: 0)
      }
    let delivered = ReceivedMessage(message: msg, isExactlyOnce: true, ackHandler: self.handler)
    let state = LockedBox(0)
    return MessageStream(
      next: { [midStreamFailure = self.midStreamFailure] in
        let step = state.withLock { value -> Int in
          let current = value
          value += 1
          return current
        }
        if step == 0 {
          return delivered
        }
        if midStreamFailure {
          throw RequestError.service(ServiceError(code: .unavailable, message: "stream dropped"))
        }
        return nil
      },
      onStop: { _ in ShutdownResult() }
    )
  }

  func pull(subscription: String, options: PullOptions) async throws -> PullResult {
    let msg = ReceivedMessage(
      message: Message(data: Data("pulled".utf8)),
      ackHandler: self.handler
    )
    return PullResult(messages: [msg])
  }
}

private func makeForwardingStream(
  _ underlying: any MessageStreamProtocol,
  intercepted: LockedBox<Int>
) -> MessageStream {
  typealias NextResult = Result<ReceivedMessage?, any Error>
  let (demandStream, demandContinuation) =
    AsyncStream<CheckedContinuation<NextResult, Never>>.makeStream()
  let pumpTask = Task {
    var demandIterator = demandStream.makeAsyncIterator()
    var current = await demandIterator.next()
    if current != nil {
      do {
        for try await item in underlying {
          guard let req = current else { break }
          current = nil
          req.resume(returning: .success(item))
          current = await demandIterator.next()
          if current == nil { break }
        }
        current?.resume(returning: .success(nil))
      } catch {
        current?.resume(returning: .failure(error))
      }
    }
    demandContinuation.finish()
    while let extra = await demandIterator.next() {
      extra.resume(returning: .success(nil))
    }
  }
  return MessageStream(
    next: {
      let result: NextResult = await withCheckedContinuation { continuation in
        if case .terminated = demandContinuation.yield(continuation) {
          continuation.resume(returning: .success(nil))
        }
      }
      guard let item = try result.get() else {
        return nil
      }
      intercepted.withLock { $0 += 1 }
      let wrapper = ForwardingAckHandler(inner: item)
      return ReceivedMessage(
        message: item.message,
        isExactlyOnce: item.isExactlyOnce,
        ackHandler: wrapper
      )
    },
    onStop: { options in
      demandContinuation.finish()
      let result = try await underlying.stop(options: options)
      _ = await pumpTask.value
      return result
    }
  )
}

private final class ForwardingSubscriber: Clients.SubscriberProtocol, Sendable {
  let inner: any Clients.SubscriberProtocol
  let intercepted = LockedBox(0)

  init(inner: any Clients.SubscriberProtocol) {
    self.inner = inner
  }

  func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    let underlying = try self.inner.subscribe(subscription: subscription, options: options)
    return makeForwardingStream(underlying, intercepted: self.intercepted)
  }

  func pull(subscription: String, options: PullOptions) async throws -> PullResult {
    let innerResult = try await self.inner.pull(subscription: subscription, options: options)
    let wrapped = innerResult.messages.map { item in
      self.intercepted.withLock { $0 += 1 }
      return ReceivedMessage(
        message: item.message,
        isExactlyOnce: item.isExactlyOnce,
        ackHandler: item.ackHandler
      )
    }
    return PullResult(messages: wrapped)
  }
}

private func expectUnimplemented(
  _ operation: () throws -> Void,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  do {
    try operation()
    Issue.record("Expected RequestError.unimplemented", sourceLocation: sourceLocation)
  } catch RequestError.unimplemented {
  } catch {
    Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
  }
}

private func expectUnimplementedAsync(
  _ operation: () async throws -> Void,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  do {
    try await operation()
    Issue.record("Expected RequestError.unimplemented", sourceLocation: sourceLocation)
  } catch RequestError.unimplemented {
  } catch {
    Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
  }
}

@Suite struct PublicAPIMockingTests {
  @Test func unimplementedProtocolDefaultsThrowUnimplemented() async throws {
    let pubClient = UnimplementedPublisherClient()
    expectUnimplemented {
      _ = try pubClient.publisher(topic: "projects/p/topics/t")
    }
    await expectUnimplementedAsync {
      _ = try await pubClient.shutdown()
    }

    let pub = UnimplementedPublisher()
    await expectUnimplementedAsync {
      _ = try await pub.publish(Message())
    }
    await expectUnimplementedAsync {
      _ = try await pub.flush()
    }
    await expectUnimplementedAsync {
      _ = try await pub.resumePublishing(orderingKey: "k")
    }
    await expectUnimplementedAsync {
      _ = try await pub.shutdown()
    }

    let blk = UnimplementedBlockingPublisher()
    await expectUnimplementedAsync {
      _ = try await blk.publish(Message(), topic: "projects/p/topics/t")
    }

    let sub = UnimplementedSubscriber()
    expectUnimplemented {
      _ = try sub.subscribe(subscription: "projects/p/subscriptions/s")
    }
    await expectUnimplementedAsync {
      _ = try await sub.pull(subscription: "projects/p/subscriptions/s")
    }

    let stream = UnimplementedStream()
    await expectUnimplementedAsync {
      _ = try await stream.stop()
    }
    await expectUnimplementedAsync {
      for try await _ in stream {}
    }

    let ackHandler = UnimplementedAckHandler()
    _ = ackHandler.ack()
    _ = ackHandler.nack()
    await expectUnimplementedAsync {
      _ = try await ackHandler.ackWithResult()
    }
    await expectUnimplementedAsync {
      _ = try await ackHandler.nackWithResult()
    }
  }

  @Test func publisherMockAndForwardingDecorator() async throws {
    let factory = ForwardingPublisherClient(inner: MockPublisherClient())
    let publisher = try factory.publisher(topic: "projects/p/topics/t")
    let res = try await publisher.publish(Message(data: Data("abc".utf8), orderingKey: "k1"))
    #expect(res == PublishResult(messageID: "mock-3"))
    _ = try await publisher.flush()
    _ = try await publisher.resumePublishing(orderingKey: "k1")
    _ = try await publisher.shutdown()
    _ = try await factory.shutdown()
    #expect(factory.createdTopics.withLock { $0 } == ["projects/p/topics/t"])

    let forwardingBlocking = ForwardingBlockingPublisher(inner: MockBlockingPublisher())
    let blockingResult = try await forwardingBlocking.publish(
      Message(), topic: "projects/p/topics/t")
    #expect(blockingResult == PublishResult(messageID: "blk-projects/p/topics/t"))
    #expect(forwardingBlocking.count.withLock { $0 } == 1)
  }

  @Test func subscriberForwardingDecoratorAndMidStreamFailure() async throws {
    let recorder = RecordingAckHandler()
    let subscriber = ForwardingSubscriber(
      inner: MockSubscriber(handler: recorder, midStreamFailure: true))
    let stream = try subscriber.subscribe(subscription: "projects/p/subscriptions/s")

    var seen: [Message] = []
    do {
      for try await received in stream {
        seen.append(received.message)
        let ackResult = try await received.ackWithResult()
        #expect(ackResult == AckResult(status: .success))
      }
      Issue.record("Expected mid-stream error")
    } catch let error as RequestError {
      guard case .service(let details) = error else {
        Issue.record("Expected service error, got \(error)")
        return
      }
      #expect(details.code == .unavailable)
    }

    #expect(seen.count == 1)
    #expect(seen[0].deliveryAttempt == 2)
    #expect(recorder.snapshot.ackWithResults == 1)
    _ = try await stream.stop()

    let pullResult = try await subscriber.pull(subscription: "projects/p/subscriptions/s")
    #expect(pullResult.messages.count == 1)
    pullResult.messages[0].ack()
    #expect(recorder.snapshot.acks == 1)
  }

  @Test func receivedMessageAutoNacksExactlyOnceWhenDroppedUnsettled() {
    let recorder = RecordingAckHandler()
    do {
      let msg = ReceivedMessage(message: Message(), ackHandler: recorder)
      _ = msg.message
    }
    #expect(recorder.snapshot == RecordingAckHandler.Counts(acks: 0, nacks: 1))

    let recorderExplicit = RecordingAckHandler()
    do {
      let msg = ReceivedMessage(message: Message(), ackHandler: recorderExplicit)
      msg.ack()
    }
    #expect(recorderExplicit.snapshot == RecordingAckHandler.Counts(acks: 1, nacks: 0))

    // Forwarding via item.ackHandler preserves ownership transfer without premature or double nacks.
    let recorderForwardedAck = RecordingAckHandler()
    do {
      let forwarded: ReceivedMessage
      do {
        let raw = ReceivedMessage(message: Message(), ackHandler: recorderForwardedAck)
        forwarded = ReceivedMessage(message: raw.message, ackHandler: raw.ackHandler)
      }
      #expect(recorderForwardedAck.snapshot == RecordingAckHandler.Counts(acks: 0, nacks: 0))
      forwarded.ack()
    }
    #expect(recorderForwardedAck.snapshot == RecordingAckHandler.Counts(acks: 1, nacks: 0))

    let recorderForwardedDrop = RecordingAckHandler()
    do {
      let raw = ReceivedMessage(message: Message(), ackHandler: recorderForwardedDrop)
      let forwarded = ReceivedMessage(message: raw.message, ackHandler: raw.ackHandler)
      _ = forwarded.message
    }
    #expect(recorderForwardedDrop.snapshot == RecordingAckHandler.Counts(acks: 0, nacks: 1))
  }

  @Test func messageStreamClosureIsSinglePass() async throws {
    let emitted = LockedBox(0)
    let stream = MessageStream(next: {
      let count = emitted.withLock { v -> Int in
        let current = v
        v += 1
        return current
      }
      if count == 0 {
        return ReceivedMessage(message: Message(), ackHandler: RecordingAckHandler())
      }
      return nil
    })
    var firstPassCount = 0
    for try await msg in stream {
      msg.ack()
      firstPassCount += 1
    }
    #expect(firstPassCount == 1)

    var secondPassCount = 0
    for try await _ in stream {
      secondPassCount += 1
    }
    #expect(secondPassCount == 0)
  }

  @Test func concreteValidationErrorsUsePublicErrorContract() throws {
    let client = try PublisherClient(
      PublisherClientOptions().with {
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      })
    #expect {
      _ = try client.publisher(topic: "short-topic")
    } throws: { error in
      if case PubSubError.emptyProjectID(resource: "short-topic") = error {
        return true
      }
      return false
    }
    #expect(
      throws: PubSubError.self
    ) {
      _ = try client.publisher(
        topic: "projects/p/topics/t",
        options: TopicPublisherOptions().with {
          $0.hedging = HedgingOptions().with {
            $0.isEnabled = true
            $0.delay = .milliseconds(10)
          }
        })
    }
    #expect(throws: PubSubError.self) {
      _ = try PublisherClient(
        PublisherClientOptions().with {
          $0.defaultTopicOptions.hedging = HedgingOptions().with {
            $0.isEnabled = true
            $0.delay = .milliseconds(10)
          }
        })
    }
  }
}
