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

extension Clients {
  /// A Swift protocol to mock a topic-bound ``Publisher``.
  ///
  /// Implement `Clients.PublisherProtocol` in unit tests using plain `import GoogleCloudPubSub`.
  public protocol PublisherProtocol: Sendable {
    /// The resolved canonical topic resource path targeted by this publisher.
    var topic: String { get }

    /// Enqueues `message` into the batcher (subject to flow control) and returns an opaque
    /// ``PublishHandle`` before awaiting wire transmission.
    ///
    /// - Parameters:
    ///   - message: The message to publish.
    ///   - options: Per-publish request options.
    /// - Returns: A ``PublishHandle`` resolving to ``PublishResult``.
    /// - Throws: ``PubSubError`` if the publisher is shut down, the message exceeds 10 MB
    ///   or contains invalid UTF-8 metadata, the ordering key is paused, or flow control
    ///   rejects the message under `.signalError`.
    func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle

    /// Flushes all currently buffered batches across every ordering key and awaits their
    /// completion.
    ///
    /// - Parameter options: Flush request options.
    /// - Returns: A ``FlushResult``.
    /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
    func flush(options: FlushOptions) async throws -> FlushResult

    /// Unpauses (uncorks) a paused `orderingKey` after an earlier permanent failure or
    /// flow-control rejection, allowing subsequent publishes for that key to proceed.
    ///
    /// Calling this method for an active (unpaused) ordering key is a safe no-op.
    ///
    /// - Parameters:
    ///   - orderingKey: The ordering key to resume.
    ///   - options: Resume request options.
    /// - Returns: A ``ResumePublishingResult``.
    /// - Throws: ``PubSubError/publisherShutDown`` or `GoogleGax.RequestError`.
    func resumePublishing(
      orderingKey: String,
      options: ResumePublishingOptions
    ) async throws -> ResumePublishingResult

    /// Rejects future publish requests, flushes pending batches, and awaits in-flight RPCs.
    ///
    /// Calling `shutdown(options:)` multiple times is idempotent.
    ///
    /// - Parameter options: Shutdown request options.
    /// - Returns: A ``ShutdownResult``.
    /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
    func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult
  }
}

extension Clients.PublisherProtocol {
  /// Default empty topic name for minimal mock implementations.
  public var topic: String { "" }

  /// Enqueues `message` for batched publishing with default options.
  public func startPublish(_ message: Message) async throws -> PublishHandle {
    try await self.startPublish(message, options: .init())
  }

  /// Default unimplemented start-publish handler throwing `GoogleGax.RequestError.unimplemented`.
  public func startPublish(_ message: Message, options: PublishOptions) async throws
    -> PublishHandle
  {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Publishes `message` through the batcher and awaits the server-assigned ``PublishResult``.
  ///
  /// - Parameters:
  ///   - message: The message to publish.
  ///   - options: Per-publish request options.
  /// - Returns: A ``PublishResult`` containing the server-assigned message ID.
  /// - Throws: `GoogleGax.RequestError` for service/transport failures or ``PubSubError``
  ///   for client-detected and ordering-key lifecycle failures.
  public func publish(
    _ message: Message,
    options: PublishOptions = .init()
  ) async throws -> PublishResult {
    let handle = try await self.startPublish(message, options: options)
    return try await handle.result()
  }

  /// Flushes all currently buffered batches using default options.
  public func flush() async throws -> FlushResult {
    try await self.flush(options: .init())
  }

  /// Default unimplemented flush handler throwing `GoogleGax.RequestError.unimplemented`.
  public func flush(options: FlushOptions) async throws -> FlushResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Resumes a paused ordering key using default options.
  public func resumePublishing(orderingKey: String) async throws -> ResumePublishingResult {
    try await self.resumePublishing(orderingKey: orderingKey, options: .init())
  }

  /// Default unimplemented ordering-key resume handler throwing `GoogleGax.RequestError.unimplemented`.
  public func resumePublishing(
    orderingKey: String,
    options: ResumePublishingOptions
  ) async throws -> ResumePublishingResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Shuts down the publisher cleanly using default options.
  public func shutdown() async throws -> ShutdownResult {
    try await self.shutdown(options: .init())
  }

  /// Default unimplemented shutdown handler throwing `GoogleGax.RequestError.unimplemented`.
  public func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

/// High-throughput, topic-scoped asynchronous batching publisher for Cloud Pub/Sub.
///
/// Obtain a `Publisher` from ``PublisherClient/publisher(topic:options:)`` to share a gRPC
/// connection pool across topics, or initialize a standalone `Publisher` directly for
/// single-topic applications.
///
/// Messages are grouped per `orderingKey` (including `""` for unordered messages) and
/// flushed when batch count, encoded bytes, or `delayThreshold` triggers. Per the
/// `google.pubsub.v1.Publish` service specification, batches are capped at 1,000 messages
/// and 10 MB (`10_000_000` bytes).
///
/// @Snippet(path: "PublisherQuickstart")
public final class Publisher: Clients.PublisherProtocol, Sendable {
  /// The resolved canonical topic resource name (`projects/{project}/topics/{topic}`).
  public let topic: String

  package let options: TopicPublisherOptions
  private let engine: TopicBatchPublisher

  /// Creates a standalone topic publisher owning its own gRPC connection pool.
  ///
  /// - Parameters:
  ///   - topic: Full topic resource name or short topic ID (requires `clientOptions.projectID`).
  ///   - clientOptions: Transport, credentials, project ID, and subchannel settings.
  ///   - options: Topic-specific options overriding `clientOptions.defaultTopicOptions`, or `nil`
  ///     to inherit `clientOptions.defaultTopicOptions`.
  /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
  ///   ``PubSubError/invalidConfiguration(description:)``.
  public convenience init(
    topic: String,
    clientOptions: PublisherClientOptions = .init(),
    options: TopicPublisherOptions? = nil
  ) throws {
    try self.init(
      topic: topic,
      clientOptions: clientOptions,
      options: options,
      clock: SystemPubSubClock(),
      environment: ProcessInfo.processInfo.environment
    )
  }

  convenience init(
    topic: String,
    clientOptions: PublisherClientOptions,
    options: TopicPublisherOptions?,
    clock: any PubSubClock,
    environment: [String: String]
  ) throws {
    if clientOptions.subchannelCount < 1 {
      throw PubSubError.invalidConfiguration(
        description:
          "PublisherClientOptions.subchannelCount (\(clientOptions.subchannelCount)) must be >= 1."
      )
    }
    let resolved = try resolvePubSubTopicName(topic, projectID: clientOptions.projectID)
    let resolvedOptions = options ?? clientOptions.defaultTopicOptions
    try validateTopicPublisherOptions(resolvedOptions)
    let pool = try GRPCChannelPool(
      from: clientOptions.client,
      subchannelCount: clientOptions.subchannelCount,
      environment: environment
    )
    self.init(
      resolvedTopic: resolved,
      options: resolvedOptions,
      pool: pool,
      ownsPool: true,
      clock: clock
    )
  }

  init(
    resolvedTopic: String,
    options: TopicPublisherOptions,
    pool: GRPCChannelPool,
    ownsPool: Bool,
    clock: any PubSubClock
  ) {
    self.topic = resolvedTopic
    self.options = options
    self.engine = TopicBatchPublisher(
      resolvedTopic: resolvedTopic,
      options: options,
      pool: pool,
      ownsPool: ownsPool,
      clock: clock
    )
  }

  /// Enqueues `message` into the topic batcher and returns a ``PublishHandle``.
  ///
  /// @Snippet(path: "PublisherStartPublish")
  /// - Parameters:
  ///   - message: The message to publish.
  ///   - options: Per-publish request options.
  /// - Returns: A ``PublishHandle`` resolving to ``PublishResult``.
  /// - Throws: ``PubSubError`` if the publisher is shut down, the message fails validation,
  ///   its ordering key is paused, or flow control rejects the message under `.signalError`.
  public func startPublish(_ message: Message, options: PublishOptions) async throws
    -> PublishHandle
  {
    try await self.engine.startPublish(message, options: options)
  }

  /// Flushes all buffered batches across every ordering key and awaits settlement.
  ///
  /// @Snippet(path: "PublisherFlushAndShutdown")
  /// - Parameter options: Flush request options.
  /// - Returns: A ``FlushResult``.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func flush(options: FlushOptions) async throws -> FlushResult {
    try await self.engine.flush(options: options)
  }

  /// Resumes a paused ordering key after an earlier failure.
  ///
  /// @Snippet(path: "PublisherOrdered")
  /// - Parameters:
  ///   - orderingKey: The ordering key to resume.
  ///   - options: Resume request options.
  /// - Returns: A ``ResumePublishingResult``.
  /// - Throws: ``PubSubError/publisherShutDown`` or `GoogleGax.RequestError`.
  public func resumePublishing(
    orderingKey: String,
    options: ResumePublishingOptions
  ) async throws -> ResumePublishingResult {
    try await self.engine.resumePublishing(orderingKey: orderingKey, options: options)
  }

  /// Drains pending batches and shuts down this topic publisher.
  ///
  /// @Snippet(path: "PublisherFlushAndShutdown")
  /// - Parameter options: Shutdown request options.
  /// - Returns: A ``ShutdownResult``.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    try await self.engine.shutdown(options: options)
  }
}
