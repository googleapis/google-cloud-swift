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

public import GoogleGax

/// Configuration for initializing a ``PublisherClient``.
public struct PublisherClientOptions: Sendable {
  /// Transport, credential, endpoint, universe domain, and logging configuration.
  public var client: GoogleGax.ClientOptions = .init()

  /// Optional Google Cloud project ID used to expand short topic IDs (containing no `"/"`)
  /// into `projects/{projectID}/topics/{topicID}`.
  ///
  /// When passing an already-qualified `projects/.../topics/...` resource path, that path's
  /// project segment is always preserved verbatim.
  public var projectID: String? = nil

  /// Number of HTTP/2 gRPC connections maintained in the shared channel pool.
  ///
  /// Defaults to `min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4)`. Values less
  /// than `1` throw ``PubSubError/invalidConfiguration(description:)``.
  public var subchannelCount: Int = defaultPubSubSubchannelCount()

  /// Default topic publisher options inherited by ``Clients/PublisherClientProtocol/publisher(topic:)``.
  public var defaultTopicOptions: TopicPublisherOptions = .init()

  /// Creates default publisher client options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Batching thresholds controlling when accumulated publish messages flush into a `Publish` RPC.
///
/// A batch flushes as soon as **any** threshold is reached. Values exceeding the current Pub/Sub
/// service limits (`1,000` messages or `10_000_000` encoded bytes per `PublishRequest`) are clamped
/// to those protocol bounds at batch execution time.
public struct BatchingOptions: Sendable, Equatable {
  /// Maximum number of messages per batch. Defaults to `100` (protocol max `1,000`).
  public var countThreshold: Int = 100

  /// Maximum encoded batch byte size before flushing. Defaults to `1_000_000` (`1 MB`; protocol max `10_000_000`).
  public var byteThreshold: Int = 1_000_000

  /// Maximum wait time from when the **first** message enters an empty batch. Defaults to `10ms`.
  public var delayThreshold: Duration = .milliseconds(10)

  /// Creates default batching options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Policy applied when local publish flow-control watermarks are reached.
///
/// - Note: Adding cases to this enumeration is not considered a breaking change.
///   Always include an `@unknown default:` clause when switching over this type.
public enum FlowControlLimitExceededBehavior: Sendable, Hashable {
  /// Do not enforce local publish watermarks (default).
  case ignore
  /// Suspend ``Publisher/startPublish(_:options:)`` callers in FIFO order until capacity drains.
  case block
  /// Reject immediately with ``PubSubError/flowControlLimitExceeded(_:)`` and zero wire RPCs.
  case signalError
}

/// Local memory and concurrency flow-control configuration for a ``Publisher``.
public struct PublisherFlowControlOptions: Sendable, Equatable {
  /// Maximum pending (buffered + in-flight) messages allowed, or `nil` for unlimited.
  public var maxPendingMessages: Int? = nil

  /// Maximum pending (buffered + in-flight) bytes allowed, or `nil` for unlimited.
  public var maxPendingBytes: Int? = nil

  /// Action taken when accepting a message would exceed ``maxPendingMessages`` or ``maxPendingBytes``.
  ///
  /// Defaults to ``FlowControlLimitExceededBehavior/ignore``. When set to
  /// ``FlowControlLimitExceededBehavior/signalError`` on a message with a non-empty `orderingKey`,
  /// rejecting the message also pauses that `orderingKey` until
  /// ``Publisher/resumePublishing(orderingKey:options:)`` is called.
  public var limitExceededBehavior: FlowControlLimitExceededBehavior = .ignore

  /// Creates default publisher flow-control options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Outbound `gzip` transport compression settings for publish RPCs.
public struct CompressionOptions: Sendable, Equatable {
  /// Whether `gzip` compression is enabled when a serialized batch exceeds ``bytesThreshold``. Defaults to `false`.
  public var isEnabled: Bool = false

  /// Minimum uncompressed payload size (in bytes) required before applying `gzip`. Defaults to `240`.
  public var bytesThreshold: Int = 240

  /// Creates default compression options (`isEnabled = false`, `bytesThreshold = 240`).
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Latency-based request hedging configuration for unkeyed publish batches.
///
/// When ``isEnabled`` is `true`:
/// - ``delay`` must be in `[100ms, 10s]`,
/// - ``maxTokens`` must be in `1...250`,
/// - ``refillRatio`` must be finite and in `0.001...0.2`.
///
/// Out-of-range values when enabled throw ``PubSubError/invalidConfiguration(description:)``
/// when constructing the ``Publisher``. Ordered messages (non-empty `orderingKey`) automatically
/// suppress concurrent hedged attempts while remaining eligible on unkeyed batches.
public struct HedgingOptions: Sendable, Equatable {
  /// Enables latency-based duplicate publish attempts for unkeyed batches. Defaults to `false`.
  public var isEnabled: Bool = false

  /// Delay after launching attempt `k` before sending hedged attempt `k + 1`. Defaults to `1s`.
  public var delay: Duration = .seconds(1)

  /// Maximum capacity of the fixed-point milli-token bucket (`1` token = `1_000` milli-tokens). Defaults to `50`.
  public var maxTokens: Int = 50

  /// Fractional tokens replenished on each successful `Publish` RPC (`0.001...0.2`). Defaults to `0.1`.
  public var refillRatio: Double = 0.1

  /// Creates default hedging options (`isEnabled = false`).
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Configuration for a topic-scoped ``Publisher``.
///
/// ```swift
/// let topicOptions = TopicPublisherOptions().with {
///   $0.batching.countThreshold = 200
///   $0.compression.isEnabled = true
/// }
/// ```
public struct TopicPublisherOptions: Sendable {
  /// Batching count, byte, and delay thresholds.
  public var batching: BatchingOptions = .init()

  /// Local pending message and byte flow-control limits.
  public var flowControl: PublisherFlowControlOptions = .init()

  /// Outbound payload `gzip` compression settings.
  public var compression: CompressionOptions = .init()

  /// Publish request hedging configuration.
  public var hedging: HedgingOptions = .init()

  /// Per-request metadata, timeout, quota project, and retry/backoff policy overrides.
  ///
  /// When `request.retryPolicy` is `nil`, the publisher defaults to ``PubSubRetryPolicy/defaultPublishPolicy``;
  /// when `request.backoffPolicy` is `nil`, it defaults to ``PubSubRetryPolicy/defaultBackoffPolicy``.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default topic publisher options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/PublisherProtocol/startPublish(_:options:)`` and ``Clients/PublisherProtocol/publish(_:options:)``.
public struct PublishOptions: Sendable {
  /// Request-level options such as custom headers or attempt timeout overrides.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default publish options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/PublisherProtocol/flush(options:)``.
public struct FlushOptions: Sendable {
  /// Request-level options.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default flush options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/PublisherProtocol/resumePublishing(orderingKey:options:)``.
public struct ResumePublishingOptions: Sendable {
  /// Request-level options.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default resume-publishing options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/PublisherProtocol/shutdown(options:)``.
public struct PublisherShutdownOptions: Sendable {
  /// Request-level options.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default publisher shutdown options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/PublisherClientProtocol/shutdown(options:)``.
public struct PublisherClientShutdownOptions: Sendable {
  /// Request-level options.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default publisher client shutdown options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Configuration for initializing a ``BlockingPublisherClient``.
public struct BlockingPublisherClientOptions: Sendable {
  /// Transport, credential, endpoint, universe domain, and logging configuration.
  public var client: GoogleGax.ClientOptions = .init()

  /// Optional Google Cloud project ID used to expand short topic IDs into
  /// `projects/{projectID}/topics/{topicID}`.
  public var projectID: String? = nil

  /// Number of HTTP/2 gRPC connections maintained in the channel pool.
  ///
  /// Defaults to `min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4)`. Values less
  /// than `1` throw ``PubSubError/invalidConfiguration(description:)``.
  public var subchannelCount: Int = defaultPubSubSubchannelCount()

  /// Default outbound payload compression settings applied to blocking publish calls.
  public var compression: CompressionOptions = .init()

  /// Creates default blocking publisher client options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for ``Clients/BlockingPublisherProtocol/publish(_:topic:options:)``.
public struct BlockingPublishOptions: Sendable {
  /// Optional per-call compression override. When `nil`, inherits the client's compression setting.
  public var compression: CompressionOptions? = nil

  /// Request-level timeout, retry policy, backoff policy, quota project, and custom headers.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default blocking publish options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
