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
@_spi(GoogleCloudInternal) import GoogleGax
import Logging
import _GoogleCloudPubSubProtos
import SwiftProtobuf

extension Clients {
  /// A Swift protocol to mock ``SubscriberClient``.
  public protocol SubscriberProtocol: Sendable {
    /// Opens an optimistic streaming pull session using default subscribe options.
    ///
    /// - Parameter subscription: Full subscription resource name (`projects/{project}/subscriptions/{sub}`)
    ///   or short subscription ID when ``SubscriberClientOptions/projectID`` is set.
    /// - Returns: A single-pass ``MessageStreamProtocol`` yielding delivered messages.
    /// - Throws: ``PubSubError/emptyProjectID(resource:)``,
    ///   ``PubSubError/invalidConfiguration(description:)``, or `GoogleGax.RequestError`.
    func subscribe(subscription: String) throws -> any MessageStreamProtocol

    /// Opens an optimistic streaming pull session returning an `AsyncSequence` of
    /// ``ReceivedMessage`` values.
    ///
    /// - Parameters:
    ///   - subscription: Full subscription resource name (`projects/{project}/subscriptions/{sub}`)
    ///     or short subscription ID when ``SubscriberClientOptions/projectID`` is set.
    ///   - options: Stream count, flow control, lease extension, keepalive, shutdown, and request options.
    /// - Returns: A single-pass ``MessageStreamProtocol`` yielding delivered messages.
    /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
    ///   ``PubSubError/invalidConfiguration(description:)``.
    func subscribe(subscription: String, options: SubscribeOptions) throws
      -> any MessageStreamProtocol

    /// Executes a managed unary pull using default pull options.
    ///
    /// - Parameter subscription: Full subscription resource name or short subscription ID when
    ///   ``SubscriberClientOptions/projectID`` is configured.
    /// - Returns: A ``PullResult`` containing zero or more ``ReceivedMessage`` instances.
    /// - Throws: `GoogleGax.RequestError` for service or transport failures, or ``PubSubError``
    ///   if resource name or configuration validation fails.
    func pull(subscription: String) async throws -> PullResult

    /// Executes a managed unary `google.pubsub.v1.Subscriber/Pull` request and enrolls
    /// received messages in automatic lease renewal and settlement tracking.
    ///
    /// - Parameters:
    ///   - subscription: Full subscription resource name or short subscription ID when
    ///     ``SubscriberClientOptions/projectID`` is configured.
    ///   - options: Batch size (`maxMessages`), `returnImmediately`, lease extension, and request options.
    /// - Returns: A ``PullResult`` containing zero or more ``ReceivedMessage`` instances.
    /// - Throws: `GoogleGax.RequestError` for service or transport failures, or
    ///   ``PubSubError`` if resource name or configuration validation fails.
    func pull(subscription: String, options: PullOptions) async throws -> PullResult
  }
}

extension Clients.SubscriberProtocol {
  /// Opens a streaming pull session using default subscribe options.
  public func subscribe(subscription: String) throws -> any MessageStreamProtocol {
    try self.subscribe(subscription: subscription, options: .init())
  }

  /// Default unimplemented subscribe handler throwing `GoogleGax.RequestError.unimplemented`.
  public func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Executes a managed unary pull using default pull options.
  public func pull(subscription: String) async throws -> PullResult {
    try await self.pull(subscription: subscription, options: .init())
  }

  /// Default unimplemented unary pull handler throwing `GoogleGax.RequestError.unimplemented`.
  public func pull(subscription: String, options: PullOptions) async throws -> PullResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

/// High-throughput Cloud Pub/Sub message subscriber supporting bidirectional
/// `StreamingPull` streams (`AsyncSequence`) and managed unary `pull`.
///
/// `SubscriberClient` connects optimistically without issuing pre-flight `GetSubscription`
/// RPCs, maintains per-stream flow control with local admission gating, renews leases using an
/// adaptive 99th-percentile ack-latency histogram, dynamically adapts to exactly-once delivery
/// subscriptions, and handles deterministic graceful shutdown.
///
/// @Snippet(path: "SubscriberSubscribe")
public final class SubscriberClient: Clients.SubscriberProtocol, Sendable {
  /// Client configuration used to initialize this instance.
  public let options: SubscriberClientOptions

  private let pool: GRPCChannelPool
  private let clock: any PubSubClock

  /// Creates a new `SubscriberClient`.
  ///
  /// - Parameter options: Transport, credentials, project ID, subchannels, and default subscribe/pull options.
  /// - Throws: ``PubSubError/invalidConfiguration(description:)`` if client or default options
  ///   contain invalid values.
  public convenience init(_ options: SubscriberClientOptions = .init()) throws {
    try self.init(
      options,
      clock: SystemPubSubClock(),
      environment: ProcessInfo.processInfo.environment
    )
  }

  init(
    _ options: SubscriberClientOptions,
    clock: any PubSubClock,
    environment: [String: String]
  ) throws {
    if options.subchannelCount < 1 {
      throw PubSubError.invalidConfiguration(
        description:
          "SubscriberClientOptions.subchannelCount (\(options.subchannelCount)) must be >= 1.")
    }
    try validateSubscribeOptions(options.defaultSubscribeOptions)
    try validatePullOptions(options.defaultPullOptions)
    self.options = options
    self.clock = clock
    self.pool = try GRPCChannelPool(
      from: options.client,
      subchannelCount: options.subchannelCount,
      environment: environment
    )
  }

  /// Opens a streaming pull session inheriting ``SubscriberClientOptions/defaultSubscribeOptions``.
  ///
  /// - Parameter subscription: Canonical subscription path or short ID when
  ///   ``SubscriberClientOptions/projectID`` is set.
  /// - Returns: A ``MessageStreamProtocol`` yielding ``ReceivedMessage`` values.
  /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
  ///   ``PubSubError/invalidConfiguration(description:)``.
  public func subscribe(subscription: String) throws -> any MessageStreamProtocol {
    try self.subscribe(subscription: subscription, options: self.options.defaultSubscribeOptions)
  }

  /// Opens a streaming pull session yielding messages via an `AsyncSequence`.
  ///
  /// @Snippet(path: "SubscriberSubscribe")
  /// - Parameters:
  ///   - subscription: Canonical subscription path or short ID when ``SubscriberClientOptions/projectID`` is set.
  ///   - options: Stream count, flow control, lease management, keepalive, and shutdown configuration.
  /// - Returns: A ``MessageStreamProtocol`` yielding ``ReceivedMessage`` values.
  /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
  ///   ``PubSubError/invalidConfiguration(description:)``.
  public func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    let resolved = try resolvePubSubSubscriptionName(
      subscription, projectID: self.options.projectID)
    try validateSubscribeOptions(options)
    let session = StreamingPullSession(
      subscription: resolved,
      options: options,
      pool: self.pool,
      clock: self.clock
    )
    return session.makeMessageStream()
  }

  /// Executes a managed unary `Pull` RPC inheriting ``SubscriberClientOptions/defaultPullOptions``.
  ///
  /// - Parameter subscription: Canonical subscription path or short ID when
  ///   ``SubscriberClientOptions/projectID`` is set.
  /// - Returns: A ``PullResult`` containing received messages ready for `ack()` / `nack()`.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func pull(subscription: String) async throws -> PullResult {
    try await self.pull(subscription: subscription, options: self.options.defaultPullOptions)
  }

  /// Executes a managed unary `Pull` RPC and enrolls received messages in lease renewal.
  ///
  /// @Snippet(path: "SubscriberPull")
  /// - Parameters:
  ///   - subscription: Canonical subscription path or short ID when ``SubscriberClientOptions/projectID`` is set.
  ///   - options: Batch size, `returnImmediately`, lease renewal, and request configuration.
  /// - Returns: A ``PullResult`` containing received messages ready for `ack()` / `nack()`.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func pull(subscription: String, options: PullOptions) async throws -> PullResult {
    let resolved = try resolvePubSubSubscriptionName(
      subscription, projectID: self.options.projectID)
    try validatePullOptions(options)

    let request = Google_Pubsub_V1_PullRequest.with {
      $0.subscription = resolved
      $0.maxMessages = Int32(min(options.maxMessages, Int(Int32.max)))
      $0.returnImmediately = options.returnImmediately
    }
    let retryPolicy =
      options.request.retryPolicy
      ?? self.options.client.retryPolicy
      ?? PubSubRetryPolicy.defaultPublishPolicy
    let backoffPolicy = options.request.backoffPolicy ?? PubSubRetryPolicy.defaultBackoffPolicy
    let throttler = options.request.retryThrottler ?? self.pool.defaultRetryThrottler
    let routing = [_RoutingMatcher.format(key: "subscription", value: resolved)]

    self.pool.pubSubLogger.logRPCDebug(
      "Sending unary Pull RPC",
      method: .pull,
      resource: resolved,
      extraMetadata: [
        "pubsub.max_messages": .stringConvertible(options.maxMessages),
        "pubsub.return_immediately": .stringConvertible(options.returnImmediately),
      ]
    )

    let response: Google_Pubsub_V1_PullResponse
    do {
      response = try await PubSubRetryExecutor.execute(
        retryPolicy: retryPolicy,
        backoffPolicy: backoffPolicy,
        throttler: throttler,
        clock: self.clock
      ) { remainingTime in
        var attemptOptions = options.request
        if let remainingTime {
          attemptOptions.attemptTimeout =
            attemptOptions.attemptTimeout.map {
              min($0, remainingTime)
            } ?? remainingTime
        }
        return try await self.pool.unary(
          descriptor: PubSubGRPCDescriptors.pull,
          request: request,
          options: attemptOptions,
          routingParams: routing
        )
      }
    } catch {
      self.pool.pubSubLogger.logTerminalError(
        error,
        method: .pull,
        resource: resolved,
        operation: "pull"
      )
      throw error
    }

    guard !response.receivedMessages.isEmpty else {
      return PullResult(messages: [])
    }

    let subOptions = SubscribeOptions().with {
      $0.maxExtension = options.maxExtension
      $0.minAckExtension = options.minAckExtension
      $0.maxAckExtension = options.maxAckExtension
      $0.enableAdaptiveAckExtension = options.enableAdaptiveAckExtension
      $0.request = options.request
    }
    let leaseManager = LeaseManager(
      subscription: resolved,
      subscribeOptions: subOptions,
      pool: self.pool,
      clock: self.clock
    )
    var leaseItems: [LeaseManager.IncomingLeaseItem] = []
    var messages: [ReceivedMessage] = []
    leaseItems.reserveCapacity(response.receivedMessages.count)
    messages.reserveCapacity(response.receivedMessages.count)

    for proto in response.receivedMessages {
      let msg = StreamingPullSession.convertProtoMessage(proto)
      let tracker = LeaseTracker(
        leaseManager: leaseManager,
        ackID: proto.ackID,
        isExactlyOnce: false,
        releaseTarget: .none
      )
      leaseItems.append(.init(ackID: proto.ackID, leaseTracker: tracker))
      messages.append(
        ReceivedMessage(
          message: msg,
          isExactlyOnce: false,
          leaseTracker: tracker
        )
      )
    }

    _ = await leaseManager.registerBatch(leaseItems, isExactlyOnce: false)
    return PullResult(messages: messages)
  }

  package func shutdown() async {
    await self.pool.shutdown()
  }
}

private func validateLeaseBounds(
  minAckExtension: Duration?,
  maxAckExtension: Duration
) throws {
  if maxAckExtension <= .zero {
    throw PubSubError.invalidConfiguration(
      description: "maxAckExtension (\(maxAckExtension)) must be > .zero.")
  }
  if let minAckExtension {
    if minAckExtension <= .zero {
      throw PubSubError.invalidConfiguration(
        description: "minAckExtension (\(minAckExtension)) must be > .zero.")
    }
    if minAckExtension > maxAckExtension {
      throw PubSubError.invalidConfiguration(
        description:
          "minAckExtension (\(minAckExtension)) must be <= maxAckExtension (\(maxAckExtension)).")
    }
  }
}

package func validateSubscribeOptions(_ options: SubscribeOptions) throws {
  if options.streamCount < 1 {
    throw PubSubError.invalidConfiguration(
      description: "SubscribeOptions.streamCount (\(options.streamCount)) must be >= 1.")
  }
  if options.maxOutstandingMessages < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "SubscribeOptions.maxOutstandingMessages (\(options.maxOutstandingMessages)) must be >= 1."
    )
  }
  if options.maxOutstandingBytes < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "SubscribeOptions.maxOutstandingBytes (\(options.maxOutstandingBytes)) must be >= 1.")
  }
  if options.keepalivePingInterval <= .zero {
    throw PubSubError.invalidConfiguration(
      description:
        "SubscribeOptions.keepalivePingInterval (\(options.keepalivePingInterval)) must be > .zero."
    )
  }
  if options.keepalivePongTimeout <= .zero {
    throw PubSubError.invalidConfiguration(
      description:
        "SubscribeOptions.keepalivePongTimeout (\(options.keepalivePongTimeout)) must be > .zero.")
  }
  if let timeout = options.defaultShutdownTimeout, timeout < .zero {
    throw PubSubError.invalidConfiguration(
      description: "SubscribeOptions.defaultShutdownTimeout (\(timeout)) must be >= .zero.")
  }
  try validateLeaseBounds(
    minAckExtension: options.minAckExtension,
    maxAckExtension: options.maxAckExtension
  )
}

package func validatePullOptions(_ options: PullOptions) throws {
  if options.maxMessages < 1 {
    throw PubSubError.invalidConfiguration(
      description: "PullOptions.maxMessages (\(options.maxMessages)) must be >= 1.")
  }
  try validateLeaseBounds(
    minAckExtension: options.minAckExtension,
    maxAckExtension: options.maxAckExtension
  )
}
