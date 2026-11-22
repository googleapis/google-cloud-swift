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

import PubSubProtos
import Foundation
import GRPCCore
import GRPCNIOTransportCore
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import GoogleAuth
import GoogleCloudPubSub
import GoogleGax
import Synchronization
import SwiftProtobuf

/// Configuration for an in-process loopback benchmark sweep.
public struct LocalBenchmarkConfig: Sendable {
  public var payloadBytes: Int
  public var totalMessages: Int
  public var batchSize: Int
  public var trials: Int

  public init(payloadBytes: Int, totalMessages: Int, batchSize: Int, trials: Int = 5) {
    self.payloadBytes = payloadBytes
    self.totalMessages = totalMessages
    self.batchSize = batchSize
    self.trials = trials
  }
}

/// Summary row comparing raw `grpc-swift-2` stub throughput against `GoogleCloudPubSub`.
public struct BenchmarkComparisonRow: Sendable {
  public let label: String
  public let payloadBytes: Int
  public let rawMessagesPerSec: Double
  public let rawMegabytesPerSec: Double
  public let veneerMessagesPerSec: Double
  public let veneerMegabytesPerSec: Double

  public var deltaPercent: Double {
    guard self.rawMessagesPerSec > 0 else { return 0 }
    return ((self.veneerMessagesPerSec - self.rawMessagesPerSec) / self.rawMessagesPerSec) * 100.0
  }

  public func formattedLine() -> String {
    String(
      format:
        "%-20@ | %6dB | raw %9.0f msgs/s (%6.1f MB/s) | veneer %9.0f msgs/s (%6.1f MB/s) | delta %+6.2f%%",
      self.label as NSString,
      self.payloadBytes,
      self.rawMessagesPerSec,
      self.rawMegabytesPerSec,
      self.veneerMessagesPerSec,
      self.veneerMegabytesPerSec,
      self.deltaPercent
    )
  }
}

/// Tail-latency comparison with and without publish hedging.
public struct HedgingLatencySummary: Sendable {
  public let unhedgedP99Millis: Double
  public let hedgedP99Millis: Double
  public let totalPublishCallsUnhedged: Int
  public let totalPublishCallsHedged: Int
}

private enum PubSubMethodDescriptors {
  static let publisherService = ServiceDescriptor(
    fullyQualifiedService: "google.pubsub.v1.Publisher")
  static let subscriberService = ServiceDescriptor(
    fullyQualifiedService: "google.pubsub.v1.Subscriber")

  static let publish = MethodDescriptor(service: publisherService, method: "Publish")
  static let streamingPull = MethodDescriptor(service: subscriberService, method: "StreamingPull")
  static let acknowledge = MethodDescriptor(service: subscriberService, method: "Acknowledge")
  static let modifyAckDeadline = MethodDescriptor(
    service: subscriberService,
    method: "ModifyAckDeadline"
  )
}

private struct PullFeedConfig: Sendable {
  var totalMessages: Int = 0
  var batchSize: Int = 100
  var payload: Data = Data()
}

private final class LoopbackService: RegistrableRPCService, Sendable {
  private struct State: Sendable {
    var pullFeed = PullFeedConfig()
    var injectTailLatency = false
    var publishCounter = 0
  }

  private let state = Mutex(State())

  func setPullFeed(_ config: PullFeedConfig) {
    self.state.withLock { $0.pullFeed = config }
  }

  func setInjectTailLatency(_ enabled: Bool) {
    self.state.withLock {
      $0.injectTailLatency = enabled
      $0.publishCounter = 0
    }
  }

  func publishCallCount() -> Int {
    self.state.withLock { $0.publishCounter }
  }

  func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
    router.registerHandler(
      forMethod: PubSubMethodDescriptors.publish,
      deserializer: ProtobufDeserializer<Google_Pubsub_V1_PublishRequest>(),
      serializer: ProtobufSerializer<Google_Pubsub_V1_PublishResponse>()
    ) { [self] request, _ in
      var iter = request.messages.makeAsyncIterator()
      guard let req = try await iter.next() else {
        return StreamingServerResponse(
          of: Google_Pubsub_V1_PublishResponse.self,
          error: RPCError(code: .invalidArgument, message: "missing PublishRequest")
        )
      }
      while try await iter.next() != nil {}
      let (shouldStall, seqStart) = self.state.withLock { s -> (Bool, Int) in
        s.publishCounter += 1
        let stall = s.injectTailLatency && s.publishCounter >= 8 && (s.publishCounter % 8 == 0)
        return (stall, s.publishCounter * 1_000)
      }
      if shouldStall {
        try? await Task.sleep(for: .milliseconds(350))
      }
      var resp = Google_Pubsub_V1_PublishResponse()
      resp.messageIds.reserveCapacity(req.messages.count)
      for i in 0..<req.messages.count {
        resp.messageIds.append("m-\(seqStart + i)")
      }
      return StreamingServerResponse(single: ServerResponse(message: resp))
    }

    router.registerHandler(
      forMethod: PubSubMethodDescriptors.acknowledge,
      deserializer: ProtobufDeserializer<Google_Pubsub_V1_AcknowledgeRequest>(),
      serializer: ProtobufSerializer<Google_Protobuf_Empty>()
    ) { request, _ in
      var iter = request.messages.makeAsyncIterator()
      _ = try await iter.next()
      while try await iter.next() != nil {}
      return StreamingServerResponse(single: ServerResponse(message: Google_Protobuf_Empty()))
    }

    router.registerHandler(
      forMethod: PubSubMethodDescriptors.modifyAckDeadline,
      deserializer: ProtobufDeserializer<Google_Pubsub_V1_ModifyAckDeadlineRequest>(),
      serializer: ProtobufSerializer<Google_Protobuf_Empty>()
    ) { request, _ in
      var iter = request.messages.makeAsyncIterator()
      _ = try await iter.next()
      while try await iter.next() != nil {}
      return StreamingServerResponse(single: ServerResponse(message: Google_Protobuf_Empty()))
    }

    router.registerHandler(
      forMethod: PubSubMethodDescriptors.streamingPull,
      deserializer: ProtobufDeserializer<Google_Pubsub_V1_StreamingPullRequest>(),
      serializer: ProtobufSerializer<Google_Pubsub_V1_StreamingPullResponse>()
    ) { [self] request, _ in
      let feed = self.state.withLock { $0.pullFeed }
      let inbound = request.messages
      return StreamingServerResponse(metadata: [:]) { writer in
        var iter = inbound.makeAsyncIterator()
        _ = try? await iter.next()
        var sent = 0
        while sent < feed.totalMessages && !Task.isCancelled {
          let count = min(feed.batchSize, feed.totalMessages - sent)
          var resp = Google_Pubsub_V1_StreamingPullResponse()
          resp.receivedMessages.reserveCapacity(count)
          for offset in 0..<count {
            var item = Google_Pubsub_V1_ReceivedMessage()
            let idx = sent + offset
            item.ackID = "ack-\(idx)"
            item.message.messageID = "msg-\(idx)"
            item.message.data = feed.payload
            resp.receivedMessages.append(item)
          }
          try await writer.write(resp)
          sent += count
        }
        // Keep the server side open until the client ends or cancels the stream.
        while let _ = try? await iter.next() {}
        return [:]
      }
    }
  }
}

/// Runs raw `grpc-swift-2` vs `GoogleCloudPubSub` loopback throughput comparisons.
public enum PubSubLocalBenchmarkRunner {
  @concurrent
  public static func runFullSuite(
    onRow: (@Sendable (BenchmarkComparisonRow) -> Void)? = nil
  ) async throws -> (
    rows: [BenchmarkComparisonRow], hedging: HedgingLatencySummary
  ) {
    let configs: [LocalBenchmarkConfig] = [
      LocalBenchmarkConfig(payloadBytes: 100, totalMessages: 20_000, batchSize: 100, trials: 5),
      LocalBenchmarkConfig(payloadBytes: 1_024, totalMessages: 20_000, batchSize: 100, trials: 5),
      LocalBenchmarkConfig(payloadBytes: 65_536, totalMessages: 1_000, batchSize: 10, trials: 5),
    ]
    var rows: [BenchmarkComparisonRow] = []
    for cfg in configs {
      let pubRow = try await Self.benchmarkPublish(config: cfg)
      onRow?(pubRow)
      rows.append(pubRow)
      let pullRow = try await Self.benchmarkStreamingPull(config: cfg)
      onRow?(pullRow)
      rows.append(pullRow)
    }
    let hedging = try await Self.benchmarkHedging(messageCount: 16)
    return (rows, hedging)
  }

  @concurrent
  public static func benchmarkPublish(config: LocalBenchmarkConfig) async throws
    -> BenchmarkComparisonRow
  {
    let service = LoopbackService()
    let (server, serveTask, port) = try await Self.startServer(service: service)
    defer {
      server.beginGracefulShutdown()
      serveTask.cancel()
    }

    let endpoint = "http://127.0.0.1:\(port)"
    let topic = "projects/bench/topics/t"
    let payload = Data(repeating: 0x42, count: config.payloadBytes)

    let transport = try HTTP2ClientTransport.Posix(
      target: .dns(host: "127.0.0.1", port: port),
      transportSecurity: .plaintext,
      config: .defaults {
        $0.http2.authority = "127.0.0.1"
        $0.http2.maxHeaderListSize = 4 * 1024 * 1024
        $0.http2.rateLimits.controlFrames = RateLimit(maxCount: 65_535, window: .seconds(10))
      },
      serviceConfig: ServiceConfig(loadBalancingConfig: [.roundRobin])
    )
    let rawClient = GRPCClient(transport: transport)
    let rawConnTask = Task { try await rawClient.runConnections() }

    let publisher = try Publisher(
      topic: topic,
      clientOptions: PublisherClientOptions().with {
        $0.projectID = "bench"
        $0.subchannelCount = 1
        $0.client.endpoint = endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      },
      options: TopicPublisherOptions().with {
        $0.batching = BatchingOptions().with { batching in
          batching.countThreshold = config.batchSize
          batching.byteThreshold = 10_000_000
          batching.delayThreshold = .milliseconds(10)
        }
      }
    )

    let warmupCount = min(2_000, config.totalMessages)
    _ = try await Self.runRawPublishOnce(
      client: rawClient,
      topic: topic,
      payload: payload,
      totalMessages: warmupCount,
      batchSize: config.batchSize
    )
    _ = try await Self.runVeneerPublishOnce(
      publisher: publisher,
      payload: payload,
      totalMessages: warmupCount
    )

    var rawTrials: [Double] = []
    var veneerTrials: [Double] = []
    for _ in 0..<config.trials {
      let rawSec = try await Self.runRawPublishOnce(
        client: rawClient,
        topic: topic,
        payload: payload,
        totalMessages: config.totalMessages,
        batchSize: config.batchSize
      )
      rawTrials.append(Double(config.totalMessages) / rawSec)

      let veneerSec = try await Self.runVeneerPublishOnce(
        publisher: publisher,
        payload: payload,
        totalMessages: config.totalMessages
      )
      veneerTrials.append(Double(config.totalMessages) / veneerSec)
    }

    _ = try? await publisher.shutdown()
    rawClient.beginGracefulShutdown()
    rawConnTask.cancel()
    _ = try? await rawConnTask.value

    let rawMedianMsgs = Self.median(rawTrials)
    let veneerMedianMsgs = Self.median(veneerTrials)
    return BenchmarkComparisonRow(
      label: "Publish (\(config.payloadBytes)B)",
      payloadBytes: config.payloadBytes,
      rawMessagesPerSec: rawMedianMsgs,
      rawMegabytesPerSec: rawMedianMsgs * Double(config.payloadBytes) / 1_000_000.0,
      veneerMessagesPerSec: veneerMedianMsgs,
      veneerMegabytesPerSec: veneerMedianMsgs * Double(config.payloadBytes) / 1_000_000.0
    )
  }

  @concurrent
  public static func benchmarkStreamingPull(config: LocalBenchmarkConfig) async throws
    -> BenchmarkComparisonRow
  {
    let service = LoopbackService()
    let (server, serveTask, port) = try await Self.startServer(service: service)
    defer {
      server.beginGracefulShutdown()
      serveTask.cancel()
    }

    let endpoint = "http://127.0.0.1:\(port)"
    let sub = "projects/bench/subscriptions/s"
    let payload = Data(repeating: 0x43, count: config.payloadBytes)

    let transport = try HTTP2ClientTransport.Posix(
      target: .dns(host: "127.0.0.1", port: port),
      transportSecurity: .plaintext,
      config: .defaults {
        $0.http2.authority = "127.0.0.1"
        $0.http2.maxHeaderListSize = 4 * 1024 * 1024
        $0.http2.rateLimits.controlFrames = RateLimit(maxCount: 65_535, window: .seconds(10))
      },
      serviceConfig: ServiceConfig(loadBalancingConfig: [.roundRobin])
    )
    let rawClient = GRPCClient(transport: transport)
    let rawConnTask = Task { try await rawClient.runConnections() }
    defer {
      rawClient.beginGracefulShutdown()
      rawConnTask.cancel()
    }

    let subClient = try SubscriberClient(
      SubscriberClientOptions().with {
        $0.projectID = "bench"
        $0.subchannelCount = 1
        $0.client.endpoint = endpoint
        $0.client.credentials = try? Credentials(configuration: .anonymous)
      }
    )

    let warmupCount = min(2_000, config.totalMessages)
    service.setPullFeed(
      PullFeedConfig(
        totalMessages: warmupCount,
        batchSize: config.batchSize,
        payload: payload
      )
    )
    _ = try await Self.runRawPullOnce(
      client: rawClient,
      subscription: sub,
      expectedMessages: warmupCount
    )
    _ = try await Self.runVeneerPullOnce(
      subscriberClient: subClient,
      subscription: sub,
      expectedMessages: warmupCount
    )

    service.setPullFeed(
      PullFeedConfig(
        totalMessages: config.totalMessages,
        batchSize: config.batchSize,
        payload: payload
      )
    )

    var rawTrials: [Double] = []
    var veneerTrials: [Double] = []
    for _ in 0..<config.trials {
      let rawSec = try await Self.runRawPullOnce(
        client: rawClient,
        subscription: sub,
        expectedMessages: config.totalMessages
      )
      rawTrials.append(Double(config.totalMessages) / rawSec)

      let veneerSec = try await Self.runVeneerPullOnce(
        subscriberClient: subClient,
        subscription: sub,
        expectedMessages: config.totalMessages
      )
      veneerTrials.append(Double(config.totalMessages) / veneerSec)
    }

    let rawMedianMsgs = Self.median(rawTrials)
    let veneerMedianMsgs = Self.median(veneerTrials)
    return BenchmarkComparisonRow(
      label: "StreamingPull",
      payloadBytes: config.payloadBytes,
      rawMessagesPerSec: rawMedianMsgs,
      rawMegabytesPerSec: rawMedianMsgs * Double(config.payloadBytes) / 1_000_000.0,
      veneerMessagesPerSec: veneerMedianMsgs,
      veneerMegabytesPerSec: veneerMedianMsgs * Double(config.payloadBytes) / 1_000_000.0
    )
  }

  @concurrent
  public static func benchmarkHedging(messageCount: Int) async throws -> HedgingLatencySummary {
    let service = LoopbackService()
    let (server, serveTask, port) = try await Self.startServer(service: service)
    defer {
      server.beginGracefulShutdown()
      serveTask.cancel()
    }

    let endpoint = "http://127.0.0.1:\(port)"
    let topic = "projects/bench/topics/hedge"

    func measure(hedgingEnabled: Bool) async throws -> (p99Ms: Double, calls: Int) {
      service.setInjectTailLatency(true)
      let startCalls = service.publishCallCount()
      let pubClient = try PublisherClient(
        PublisherClientOptions().with {
          $0.projectID = "bench"
          $0.subchannelCount = 1
          $0.client.endpoint = endpoint
          $0.client.credentials = try? Credentials(configuration: .anonymous)
        }
      )
      let pub = try pubClient.publisher(
        topic: topic,
        options: TopicPublisherOptions().with {
          $0.batching = BatchingOptions().with { batching in
            batching.countThreshold = 1
            batching.delayThreshold = .milliseconds(1)
          }
          $0.hedging = HedgingOptions().with { hedge in
            hedge.isEnabled = hedgingEnabled
            hedge.delay = .milliseconds(100)
            hedge.maxTokens = 50
            hedge.refillRatio = 0.2
          }
        }
      )
      let clock = ContinuousClock()
      let msg = Message(data: Data("hedge-payload".utf8))
      var latencies: [Double] = []
      latencies.reserveCapacity(messageCount)
      for _ in 0..<messageCount {
        let t0 = clock.now
        _ = try await pub.publish(msg)
        latencies.append(Self.durationSeconds(clock.now - t0) * 1_000.0)
      }
      _ = try await pubClient.shutdown()
      latencies.sort()
      let idx = min(latencies.count - 1, Int(Double(latencies.count - 1) * 0.99))
      return (latencies[idx], service.publishCallCount() - startCalls)
    }

    let unhedged = try await measure(hedgingEnabled: false)
    let hedged = try await measure(hedgingEnabled: true)
    return HedgingLatencySummary(
      unhedgedP99Millis: unhedged.p99Ms,
      hedgedP99Millis: hedged.p99Ms,
      totalPublishCallsUnhedged: unhedged.calls,
      totalPublishCallsHedged: hedged.calls
    )
  }

  private static func startServer(service: LoopbackService) async throws -> (
    GRPCServer<HTTP2ServerTransport.Posix>, Task<Void, any Error>, Int
  ) {
    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: 0),
      transportSecurity: .plaintext,
      config: .defaults {
        $0.rpc.maxRequestPayloadSize = 20 * 1024 * 1024
        $0.http2.maxHeaderListSize = 4 * 1024 * 1024
        $0.http2.maxConcurrentStreams = 512
        $0.http2.rateLimits.controlFrames = RateLimit(maxCount: 65_535, window: .seconds(10))
      }
    )
    let server = GRPCServer(transport: transport, services: [service])
    let task = Task {
      try await server.serve()
    }
    let address = try await transport.listeningAddress
    guard let ipv4 = address.ipv4 else {
      task.cancel()
      server.beginGracefulShutdown()
      throw PubSubError.invalidConfiguration(description: "Expected IPv4 listening address")
    }
    return (server, task, ipv4.port)
  }

  private static func runRawPublishOnce(
    client: GRPCClient<HTTP2ClientTransport.Posix>,
    topic: String,
    payload: Data,
    totalMessages: Int,
    batchSize: Int
  ) async throws -> Double {
    var mutableCallOptions = CallOptions.defaults
    mutableCallOptions.maxRequestMessageBytes = 20 * 1024 * 1024
    mutableCallOptions.maxResponseMessageBytes = 20 * 1024 * 1024
    let callOptions = mutableCallOptions

    let metadata: Metadata = [
      "x-goog-request-params": "topic=\(topic)",
      "x-goog-api-client": "gl-swift/6.0 bench/1.0",
    ]
    let clock = ContinuousClock()
    let t0 = clock.now

    try await withThrowingTaskGroup(of: Void.self) { group in
      var inFlight = 0
      var currentBatch: [Google_Pubsub_V1_PubsubMessage] = []
      currentBatch.reserveCapacity(batchSize)
      for _ in 0..<totalMessages {
        var item = Google_Pubsub_V1_PubsubMessage()
        item.data = payload
        currentBatch.append(item)
        if currentBatch.count >= batchSize {
          let sealed = currentBatch
          currentBatch = []
          currentBatch.reserveCapacity(batchSize)
          if inFlight >= 64 {
            try await group.next()
            inFlight -= 1
          }
          inFlight += 1
          group.addTask {
            var req = Google_Pubsub_V1_PublishRequest()
            req.topic = topic
            req.messages = sealed
            _ = try await client.unary(
              request: ClientRequest(message: req, metadata: metadata),
              descriptor: PubSubMethodDescriptors.publish,
              serializer: ProtobufSerializer<Google_Pubsub_V1_PublishRequest>(),
              deserializer: ProtobufDeserializer<Google_Pubsub_V1_PublishResponse>(),
              options: callOptions,
              onResponse: { response in
                switch response.accepted {
                case .failure(let error):
                  throw error
                case .success(let contents):
                  return try contents.message.get()
                }
              }
            )
          }
        }
      }
      if !currentBatch.isEmpty {
        let sealed = currentBatch
        group.addTask {
          var req = Google_Pubsub_V1_PublishRequest()
          req.topic = topic
          req.messages = sealed
          _ = try await client.unary(
            request: ClientRequest(message: req, metadata: metadata),
            descriptor: PubSubMethodDescriptors.publish,
            serializer: ProtobufSerializer<Google_Pubsub_V1_PublishRequest>(),
            deserializer: ProtobufDeserializer<Google_Pubsub_V1_PublishResponse>(),
            options: callOptions,
            onResponse: { response in
              switch response.accepted {
              case .failure(let error):
                throw error
              case .success(let contents):
                return try contents.message.get()
              }
            }
          )
        }
      }
      try await group.waitForAll()
    }

    return Self.durationSeconds(clock.now - t0)
  }

  private static func runVeneerPublishOnce(
    publisher: Publisher,
    payload: Data,
    totalMessages: Int
  ) async throws -> Double {
    let message = Message(data: payload)
    let clock = ContinuousClock()
    let t0 = clock.now
    var handles: [PublishHandle] = []
    handles.reserveCapacity(totalMessages)
    for _ in 0..<totalMessages {
      handles.append(try await publisher.startPublish(message))
    }
    _ = try await publisher.flush()
    for handle in handles {
      _ = try await handle.result()
    }
    return Self.durationSeconds(clock.now - t0)
  }

  private static func runRawPullOnce(
    client: GRPCClient<HTTP2ClientTransport.Posix>,
    subscription: String,
    expectedMessages: Int
  ) async throws -> Double {
    var mutableCallOptions = CallOptions.defaults
    mutableCallOptions.maxRequestMessageBytes = 20 * 1024 * 1024
    mutableCallOptions.maxResponseMessageBytes = 20 * 1024 * 1024
    let callOptions = mutableCallOptions
    let metadata: Metadata = [
      "x-goog-request-params": "subscription=\(subscription)",
      "x-goog-api-client": "gl-swift/6.0 bench/1.0",
    ]
    let clock = ContinuousClock()
    let t0 = clock.now

    let (outboundStream, outboundContinuation) =
      AsyncStream<Google_Pubsub_V1_StreamingPullRequest>.makeStream()
    var frame0 = Google_Pubsub_V1_StreamingPullRequest()
    frame0.subscription = subscription
    frame0.streamAckDeadlineSeconds = 60
    frame0.maxOutstandingMessages = Int64(max(1_000, expectedMessages))
    frame0.maxOutstandingBytes = 100 * 1024 * 1024
    frame0.protocolVersion = 1
    outboundContinuation.yield(frame0)

    let request = StreamingClientRequest<Google_Pubsub_V1_StreamingPullRequest>(
      metadata: metadata
    ) { writer in
      for await frame in outboundStream {
        try await writer.write(frame)
      }
    }

    let elapsed = try await client.bidirectionalStreaming(
      request: request,
      descriptor: PubSubMethodDescriptors.streamingPull,
      serializer: ProtobufSerializer<Google_Pubsub_V1_StreamingPullRequest>(),
      deserializer: ProtobufDeserializer<Google_Pubsub_V1_StreamingPullResponse>(),
      options: callOptions
    ) { response in
      defer { outboundContinuation.finish() }
      switch response.accepted {
      case .failure(let error):
        throw error
      case .success(let contents):
        var count = 0
        var ackBuffer: [String] = []
        ackBuffer.reserveCapacity(1_000)
        try await withThrowingTaskGroup(of: Void.self) { ackGroup in
          for try await part in contents.bodyParts {
            guard case .message(let msg) = part else { continue }
            for rec in msg.receivedMessages {
              _ = Message(
                data: rec.message.data,
                attributes: rec.message.attributes,
                orderingKey: rec.message.orderingKey
              )
              ackBuffer.append(rec.ackID)
              count += 1
            }
            if ackBuffer.count >= 1_000 || count >= expectedMessages {
              let batchAckIDs = ackBuffer
              ackBuffer = []
              ackGroup.addTask {
                var ackReq = Google_Pubsub_V1_AcknowledgeRequest()
                ackReq.subscription = subscription
                ackReq.ackIds = batchAckIDs
                _ = try await client.unary(
                  request: ClientRequest(message: ackReq, metadata: metadata),
                  descriptor: PubSubMethodDescriptors.acknowledge,
                  serializer: ProtobufSerializer<Google_Pubsub_V1_AcknowledgeRequest>(),
                  deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
                  options: callOptions,
                  onResponse: { ackResp in
                    switch ackResp.accepted {
                    case .failure(let err): throw err
                    case .success(let c): return try c.message.get()
                    }
                  }
                )
              }
            }
            if count >= expectedMessages {
              outboundContinuation.finish()
              break
            }
          }
          try await ackGroup.waitForAll()
        }
        return Self.durationSeconds(clock.now - t0)
      }
    }

    return elapsed
  }

  private static func runVeneerPullOnce(
    subscriberClient: SubscriberClient,
    subscription: String,
    expectedMessages: Int
  ) async throws -> Double {
    let options = SubscribeOptions().with {
      $0.streamCount = 1
      $0.maxOutstandingMessages = max(1_000, expectedMessages)
      $0.maxOutstandingBytes = 100 * 1024 * 1024
    }
    let clock = ContinuousClock()
    let t0 = clock.now
    let stream = try subscriberClient.subscribe(subscription: subscription, options: options)
    var count = 0
    for try await received in stream {
      received.ack()
      count += 1
      if count >= expectedMessages {
        break
      }
    }
    let elapsed = Self.durationSeconds(clock.now - t0)
    _ = try await stream.stop()
    return elapsed
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted[sorted.count / 2]
  }

  private static func durationSeconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return max(1e-9, Double(seconds) + Double(attoseconds) / 1e18)
  }
}
