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

import ArgumentParser
import Foundation
import GoogleAuth
import GoogleCloudPubSub
import GoogleGax

/// Selects which data-plane path ``PubSubThroughput`` benchmarks.
public enum PubSubBenchmarkMode: String, ExpressibleByArgument, CaseIterable, Sendable {
  case publish
  case subscribe
}

/// Summary throughput and tail-latency metrics using decimal `MB/s` (`10^6 bytes/sec`).
public struct ThroughputMetrics: Sendable, Codable, Equatable {
  public let mode: String
  public let totalMessages: Int
  public let totalBytes: Int
  public let elapsedSeconds: Double
  public let messagesPerSecond: Double
  public let megabytesPerSecond: Double
  public let p50LatencyMillis: Double
  public let p99LatencyMillis: Double

  public init(
    mode: String,
    totalMessages: Int,
    totalBytes: Int,
    elapsedSeconds: Double,
    messagesPerSecond: Double,
    megabytesPerSecond: Double,
    p50LatencyMillis: Double,
    p99LatencyMillis: Double
  ) {
    self.mode = mode
    self.totalMessages = totalMessages
    self.totalBytes = totalBytes
    self.elapsedSeconds = elapsedSeconds
    self.messagesPerSecond = messagesPerSecond
    self.megabytesPerSecond = megabytesPerSecond
    self.p50LatencyMillis = p50LatencyMillis
    self.p99LatencyMillis = p99LatencyMillis
  }

  public static func compute(
    mode: String,
    totalMessages: Int,
    totalBytes: Int,
    elapsedSeconds: Double,
    latenciesMillis: [Double]
  ) -> ThroughputMetrics {
    let safeElapsed = max(elapsedSeconds, 1e-9)
    let msgsPerSec = Double(totalMessages) / safeElapsed
    let mbPerSec = Double(totalBytes) / safeElapsed / 1_000_000.0
    let sorted = latenciesMillis.sorted()
    let p50 = Self.quantile(sorted: sorted, fraction: 0.50)
    let p99 = Self.quantile(sorted: sorted, fraction: 0.99)
    return ThroughputMetrics(
      mode: mode,
      totalMessages: totalMessages,
      totalBytes: totalBytes,
      elapsedSeconds: elapsedSeconds,
      messagesPerSecond: msgsPerSec,
      megabytesPerSecond: mbPerSec,
      p50LatencyMillis: p50,
      p99LatencyMillis: p99
    )
  }

  public func formattedCSVRow() -> String {
    String(
      format: "%@,%d,%d,%.3f,%.1f,%.2f,%.3f,%.3f",
      self.mode,
      self.totalMessages,
      self.totalBytes,
      self.elapsedSeconds,
      self.messagesPerSecond,
      self.megabytesPerSecond,
      self.p50LatencyMillis,
      self.p99LatencyMillis
    )
  }

  public static let csvHeader =
    "mode,messages,bytes,elapsed_s,msgs_per_sec,mb_per_sec_1e6,p50_ms,p99_ms"

  private static func quantile(sorted: [Double], fraction: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = min(
      sorted.count - 1,
      max(0, Int((Double(sorted.count - 1) * fraction).rounded(.toNearestOrAwayFromZero)))
    )
    return sorted[index]
  }
}

/// Live Cloud Pub/Sub throughput and endurance CLI for `GoogleCloudPubSub`.
public struct PubSubThroughput: AsyncParsableCommand, Sendable {
  public static let configuration = CommandConfiguration(
    commandName: "PubSubThroughput",
    abstract: "Throughput and endurance benchmark for GoogleCloudPubSub."
  )

  @Option(name: .customLong("mode"), help: "Benchmark mode: publish or subscribe.")
  public var mode: PubSubBenchmarkMode = .publish

  @Option(
    name: [.customLong("project"), .customLong("project-id")],
    help: "Google Cloud project ID."
  )
  public var projectID: String

  @Option(name: .customLong("topic"), help: "Topic ID or full topic name for publish mode.")
  public var topic: String = ""

  @Option(
    name: .customLong("subscription"),
    help: "Subscription ID or full subscription name for subscribe mode."
  )
  public var subscription: String = ""

  @Option(
    name: .customLong("endpoint"), help: "Optional endpoint override (for regional or emulator).")
  public var endpoint: String?

  @Option(name: .customLong("payload-size"), help: "Message payload size in bytes.")
  public var payloadSize: Int = 1_024

  @Option(name: .customLong("batch-size"), help: "Publisher batch count threshold.")
  public var batchSize: Int = 100

  @Option(name: .customLong("batch-bytes"), help: "Publisher batch byte threshold.")
  public var batchBytes: Int = 1_000_000

  @Option(name: .customLong("channels"), help: "Number of gRPC subchannels.")
  public var channels: Int = 4

  @Option(name: .customLong("streams"), help: "Number of StreamingPull streams.")
  public var streams: Int = 16

  @Option(
    name: .customLong("ordering-keys"),
    help: "Number of distinct ordering keys to round-robin (0 disables ordering keys)."
  )
  public var orderingKeys: Int = 0

  @Option(name: .customLong("total-messages"), help: "Maximum number of messages to transfer.")
  public var totalMessages: Int = 100_000

  @Option(
    name: .customLong("duration-seconds"),
    help: "Optional wall-clock limit in seconds when in endurance or subscribe mode."
  )
  public var durationSeconds: Int?

  @Option(
    name: .customLong("inflight-limit"),
    help: "Maximum in-flight publish handles awaited concurrently."
  )
  public var inflightLimit: Int = 4_000

  @Flag(name: .customLong("endurance"), help: "Run until duration-seconds elapses.")
  public var endurance: Bool = false

  @Flag(name: .customLong("json"), help: "Emit machine-readable JSON instead of CSV.")
  public var json: Bool = false

  public init() {}

  public mutating func validate() throws {
    if self.payloadSize < 0 {
      throw ValidationError("--payload-size must be >= 0")
    }
    if self.batchSize < 1 {
      throw ValidationError("--batch-size must be >= 1")
    }
    if self.batchBytes < 1 {
      throw ValidationError("--batch-bytes must be >= 1")
    }
    if self.channels < 1 {
      throw ValidationError("--channels must be >= 1")
    }
    if self.streams < 1 {
      throw ValidationError("--streams must be >= 1")
    }
    if self.orderingKeys < 0 {
      throw ValidationError("--ordering-keys must be >= 0")
    }
    if self.totalMessages < 1 && !self.endurance {
      throw ValidationError("--total-messages must be >= 1 unless --endurance is set")
    }
    if self.inflightLimit < 1 {
      throw ValidationError("--inflight-limit must be >= 1")
    }
    switch self.mode {
    case .publish where self.topic.isEmpty:
      throw ValidationError("--topic is required when --mode=publish")
    case .subscribe where self.subscription.isEmpty:
      throw ValidationError("--subscription is required when --mode=subscribe")
    default:
      break
    }
  }

  public func makeClientOptions() -> GoogleGax.ClientOptions {
    var options = GoogleGax.ClientOptions()
    if let endpoint = self.endpoint, !endpoint.isEmpty {
      options.endpoint = endpoint
      if endpoint.hasPrefix("http://") {
        options.credentials = try? GoogleAuth.Credentials(configuration: .anonymous)
      }
    }
    return options
  }

  public func makeTopicPublisherOptions() -> TopicPublisherOptions {
    TopicPublisherOptions().with {
      $0.batching = BatchingOptions().with { batching in
        batching.countThreshold = self.batchSize
        batching.byteThreshold = self.batchBytes
        batching.delayThreshold = .milliseconds(10)
      }
      $0.flowControl = PublisherFlowControlOptions().with { fc in
        fc.maxPendingMessages = max(self.inflightLimit, self.batchSize * 10)
        fc.maxPendingBytes = max(self.batchBytes * 20, self.payloadSize * self.inflightLimit)
        fc.limitExceededBehavior = .block
      }
    }
  }

  public func makeSubscribeOptions() -> SubscribeOptions {
    SubscribeOptions().with {
      $0.streamCount = self.streams
      $0.maxOutstandingMessages = max(1_000, self.batchSize * 10)
      $0.maxOutstandingBytes = max(100 * 1024 * 1024, self.batchBytes * 16)
      $0.enablePerStreamFlowControl = true
    }
  }

  public func run() async throws {
    let clientOptions = self.makeClientOptions()
    let metrics: ThroughputMetrics
    switch self.mode {
    case .publish:
      let publisherClient = try PublisherClient(
        PublisherClientOptions().with {
          $0.client = clientOptions
          $0.projectID = self.projectID
          $0.subchannelCount = self.channels
          $0.defaultTopicOptions = self.makeTopicPublisherOptions()
        }
      )
      do {
        let publisher = try publisherClient.publisher(topic: self.topic)
        let deadline = self.durationSeconds.map { Duration.seconds($0) }
        metrics = try await Self.runPublishBenchmark(
          publisher: publisher,
          payloadSize: self.payloadSize,
          totalMessages: self.endurance ? Int.max : self.totalMessages,
          orderingKeys: self.orderingKeys,
          inflightLimit: self.inflightLimit,
          duration: deadline
        )
        _ = try await publisherClient.shutdown()
      } catch {
        _ = try? await publisherClient.shutdown()
        throw error
      }

    case .subscribe:
      let subscriberClient = try SubscriberClient(
        SubscriberClientOptions().with {
          $0.client = clientOptions
          $0.projectID = self.projectID
          $0.subchannelCount = self.channels
          $0.defaultSubscribeOptions = self.makeSubscribeOptions()
        }
      )
      let deadline = self.durationSeconds.map { Duration.seconds($0) }
      metrics = try await Self.runSubscribeBenchmark(
        subscriber: subscriberClient,
        subscription: self.subscription,
        options: self.makeSubscribeOptions(),
        maxMessages: self.endurance ? Int.max : self.totalMessages,
        duration: deadline
      )
    }

    Self.printMetrics(metrics, asJSON: self.json)
  }

  @concurrent
  public static func runPublishBenchmark(
    publisher: any Clients.PublisherProtocol,
    payloadSize: Int,
    totalMessages: Int,
    orderingKeys: Int = 0,
    inflightLimit: Int = 4_000,
    duration: Duration? = nil
  ) async throws -> ThroughputMetrics {
    let clock = ContinuousClock()
    let payload = Data(repeating: 0x41, count: payloadSize)
    let start = clock.now
    let stopAt = duration.map { start.advanced(by: $0) }
    var latenciesMillis: [Double] = []
    if totalMessages < 250_000 {
      latenciesMillis.reserveCapacity(totalMessages)
    }

    var pending: [(start: ContinuousClock.Instant, handle: PublishHandle)] = []
    pending.reserveCapacity(inflightLimit)
    var sent = 0
    var completed = 0
    var bytesCompleted = 0

    func drainBatch(_ items: [(start: ContinuousClock.Instant, handle: PublishHandle)])
      async throws
    {
      for entry in items {
        _ = try await entry.handle.result()
        let dt = clock.now - entry.start
        latenciesMillis.append(Self.durationMillis(dt))
        completed += 1
        bytesCompleted += payloadSize
      }
    }

    while sent < totalMessages {
      if let stopAt, clock.now >= stopAt {
        break
      }
      let key = orderingKeys > 0 ? "key-\(sent % orderingKeys)" : ""
      let msg = Message(data: payload, orderingKey: key)
      let enqueuedAt = clock.now
      let handle = try await publisher.startPublish(msg)
      pending.append((enqueuedAt, handle))
      sent += 1
      if pending.count >= inflightLimit {
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        try await drainBatch(batch)
      }
    }

    if !pending.isEmpty {
      try await drainBatch(pending)
    }
    _ = try await publisher.flush()
    let elapsed = clock.now - start
    return ThroughputMetrics.compute(
      mode: "publish",
      totalMessages: completed,
      totalBytes: bytesCompleted,
      elapsedSeconds: Self.durationSeconds(elapsed),
      latenciesMillis: latenciesMillis
    )
  }

  @concurrent
  public static func runSubscribeBenchmark(
    subscriber: any Clients.SubscriberProtocol,
    subscription: String,
    options: SubscribeOptions = .init(),
    maxMessages: Int,
    duration: Duration? = nil
  ) async throws -> ThroughputMetrics {
    let clock = ContinuousClock()
    let start = clock.now
    let stream = try subscriber.subscribe(subscription: subscription, options: options)

    let watchdog: Task<Void, Never>? = duration.map { limit in
      Task {
        try? await Task.sleep(for: limit)
        _ = try? await stream.stop()
      }
    }
    defer { watchdog?.cancel() }

    var receivedCount = 0
    var receivedBytes = 0
    var latenciesMillis: [Double] = []
    for try await received in stream {
      let recvStart = clock.now
      receivedBytes += received.message.data.count
      receivedCount += 1
      received.ack()
      latenciesMillis.append(Self.durationMillis(clock.now - recvStart))
      if receivedCount >= maxMessages {
        break
      }
    }
    _ = try await stream.stop()
    let elapsed = clock.now - start
    return ThroughputMetrics.compute(
      mode: "subscribe",
      totalMessages: receivedCount,
      totalBytes: receivedBytes,
      elapsedSeconds: Self.durationSeconds(elapsed),
      latenciesMillis: latenciesMillis
    )
  }

  public static func printMetrics(_ metrics: ThroughputMetrics, asJSON: Bool) {
    if asJSON {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      if let data = try? encoder.encode(metrics), let json = String(data: data, encoding: .utf8) {
        print(json)
      }
    } else {
      print(ThroughputMetrics.csvHeader)
      print(metrics.formattedCSVRow())
    }
  }

  private static func durationSeconds(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  private static func durationMillis(_ duration: Duration) -> Double {
    Self.durationSeconds(duration) * 1_000.0
  }
}
