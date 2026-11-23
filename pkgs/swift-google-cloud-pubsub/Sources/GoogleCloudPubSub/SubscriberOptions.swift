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

/// Configuration for initializing a ``SubscriberClient``.
public struct SubscriberClientOptions: Sendable {
  /// Transport, credential, endpoint, universe domain, and logging configuration.
  public var client: GoogleGax.ClientOptions = .init()

  /// Optional Google Cloud project ID used to expand short subscription IDs
  /// (containing no `"/"`) into `projects/{projectID}/subscriptions/{subscriptionID}`.
  ///
  /// When passing an already-qualified `projects/.../subscriptions/...` resource path, that
  /// path's project segment is always preserved verbatim.
  public var projectID: String? = nil

  /// Number of HTTP/2 gRPC connections maintained in the shared channel pool.
  ///
  /// Defaults to `min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4)`. Values less
  /// than `1` throw ``PubSubError/invalidConfiguration(description:)``.
  public var subchannelCount: Int = defaultPubSubSubchannelCount()

  /// Default streaming pull options inherited by ``Clients/SubscriberProtocol/subscribe(subscription:)``.
  public var defaultSubscribeOptions: SubscribeOptions = .init()

  /// Default unary pull options inherited by ``Clients/SubscriberProtocol/pull(subscription:)``.
  public var defaultPullOptions: PullOptions = .init()

  /// Creates default subscriber client options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Shutdown policy for stopping a ``MessageStreamProtocol``.
///
/// - Note: Adding cases to this enumeration is not considered a breaking change.
///   Always include an `@unknown default:` clause when switching over this type.
public enum ShutdownBehavior: Sendable, Hashable {
  /// Stop pulling new messages, continue extending leases for already-delivered
  /// unsettled messages until they settle or `timeout` elapses, and bulk-nack
  /// any remaining unsettled messages once `timeout` expires (default).
  case waitForProcessing
  /// Stop pulling new messages, immediately bulk-nack all unsettled (delivered and
  /// gated) messages in chunks, and close the stream.
  case nackImmediately
}

/// Configuration for opening a streaming pull session via ``SubscriberClient/subscribe(subscription:options:)``.
///
/// ```swift
/// let subscribeOptions = SubscribeOptions().with {
///   $0.streamCount = 2
///   $0.maxOutstandingMessages = 500
///   $0.maxExtension = .seconds(1_800)
/// }
/// ```
public struct SubscribeOptions: Sendable {
  /// Number of concurrent `StreamingPull` streams opened by the session. Defaults to `1`.
  public var streamCount: Int = 1

  /// Maximum outstanding unsettled messages permitted **per stream**. Defaults to `1_000`.
  public var maxOutstandingMessages: Int = 1_000

  /// Maximum outstanding unsettled bytes permitted **per stream**. Defaults to `100 MiB` (`104_857_600`).
  public var maxOutstandingBytes: Int = 100 * 1024 * 1024

  /// Whether per-stream server flow-control limits are advertised in the initial `StreamingPull` frame.
  ///
  /// Defaults to `true`.
  public var enablePerStreamFlowControl: Bool = true

  /// Total maximum duration the library automatically renews the lease for an unsettled message.
  ///
  /// Defaults to `3_600s` (60 minutes). Setting `<= .zero` disables automatic renewal beyond initial receipt.
  public var maxExtension: Duration = .seconds(3_600)

  /// Minimum lease extension duration used per `ModifyAckDeadline` renewal.
  ///
  /// When `nil`, defaults to `.seconds(10)` on at-least-once subscriptions and dynamically
  /// switches to `.seconds(60)` when the server reports `exactly_once_delivery_enabled = true`.
  public var minAckExtension: Duration? = nil

  /// Maximum lease extension duration used per `ModifyAckDeadline` renewal (clamped to `[10s, 600s]`).
  ///
  /// Defaults to `.seconds(600)`.
  public var maxAckExtension: Duration = .seconds(600)

  /// Initial stream acknowledgment deadline advertised in Frame 0 (clamped to `[10s, 600s]`).
  ///
  /// Defaults to `.seconds(60)`.
  public var streamAckDeadline: Duration = .seconds(60)

  /// Enables adaptive 99th-percentile ack-latency lease extension sizing within
  /// `[effectiveMinAckExtension, maxAckExtension]`. Defaults to `true`.
  public var enableAdaptiveAckExtension: Bool = true

  /// Interval between empty keepalive pings on open streams. Defaults to `30s`.
  public var keepalivePingInterval: Duration = .seconds(30)

  /// Maximum wait for a server response after emitting a keepalive ping before recycling the stream. Defaults to `15s`.
  public var keepalivePongTimeout: Duration = .seconds(15)

  /// Optional explicit `client_id` sent on initial `StreamingPull` requests across reconnects.
  ///
  /// When `nil` (default), a UUID string is generated per stream and preserved across reconnects.
  public var clientID: String? = nil

  /// Default shutdown behavior used when ``MessageStreamProtocol/stop(options:)`` omits `behavior`.
  public var defaultShutdownBehavior: ShutdownBehavior = .waitForProcessing

  /// Default maximum wait duration used when ``MessageStreamProtocol/stop(options:)`` omits `timeout`.
  public var defaultShutdownTimeout: Duration? = nil

  /// Request-level options such as custom headers, quota project, and retry/backoff policies.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default subscribe options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for stopping a ``MessageStreamProtocol``.
public struct SubscriberShutdownOptions: Sendable {
  /// Optional override of ``SubscribeOptions/defaultShutdownBehavior``.
  public var behavior: ShutdownBehavior? = nil

  /// Optional maximum time to wait for pending settlements (`.zero` completes immediately; `nil` inherits default or waits unboundedly).
  public var timeout: Duration? = nil

  /// Request-level options.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default subscriber shutdown options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for managed unary pull via ``SubscriberClient/pull(subscription:options:)``.
///
/// ```swift
/// let pullOptions = PullOptions().with {
///   $0.maxMessages = 25
///   $0.returnImmediately = true
/// }
/// ```
public struct PullOptions: Sendable {
  /// Maximum number of messages requested in the unary `Pull` RPC (`>= 1`). Defaults to `100`.
  public var maxMessages: Int = 100

  /// Whether the `Pull` RPC should return immediately instead of long-polling when no messages are available.
  ///
  /// Defaults to `false`.
  public var returnImmediately: Bool = false

  /// Total maximum duration the library automatically renews leases for pulled messages. Defaults to `3_600s`.
  public var maxExtension: Duration = .seconds(3_600)

  /// Optional minimum `ModifyAckDeadline` renewal extension duration.
  public var minAckExtension: Duration? = nil

  /// Maximum `ModifyAckDeadline` renewal extension duration (clamped to `[10s, 600s]`). Defaults to `600s`.
  public var maxAckExtension: Duration = .seconds(600)

  /// Enables adaptive 99th-percentile ack-latency lease extension sizing. Defaults to `true`.
  public var enableAdaptiveAckExtension: Bool = true

  /// Request-level options such as timeout, retry policy, quota project, and custom headers.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default unary pull options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for acknowledging a ``ReceivedMessage``.
public struct AckOptions: Sendable {
  /// Request-level options such as custom headers or attempt timeout overrides.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default acknowledgment options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// Options for negatively acknowledging a ``ReceivedMessage``.
public struct NackOptions: Sendable {
  /// Request-level options such as custom headers or attempt timeout overrides.
  public var request: GoogleGax.RequestOptions = .init()

  /// Creates default negative acknowledgment options.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
