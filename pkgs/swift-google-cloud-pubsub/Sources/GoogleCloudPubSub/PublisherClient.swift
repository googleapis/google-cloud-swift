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
  /// A Swift protocol to mock ``PublisherClient``.
  ///
  /// Change your functions to receive `some Clients.PublisherClientProtocol` or
  /// `any Clients.PublisherClientProtocol` and pass a mock implementation in unit tests.
  public protocol PublisherClientProtocol: Sendable {
    /// Creates a topic-scoped publisher using the client's configured default topic options.
    ///
    /// - Parameter topic: Full topic resource name (`projects/{project}/topics/{topic}`) or short
    ///   topic ID when ``PublisherClientOptions/projectID`` is configured.
    /// - Returns: A publisher bound to `topic`.
    /// - Throws: ``PubSubError/emptyProjectID(resource:)``,
    ///   ``PubSubError/invalidConfiguration(description:)``, or `GoogleGax.RequestError`.
    func publisher(topic: String) throws -> any PublisherProtocol

    /// Creates a topic-scoped publisher sharing this client's underlying gRPC connection pool.
    ///
    /// - Parameters:
    ///   - topic: Full topic resource name (`projects/{project}/topics/{topic}`) or short
    ///     topic ID when ``PublisherClientOptions/projectID`` is configured.
    ///   - options: Topic-specific batching, flow-control, compression, hedging, and retry options.
    /// - Returns: A publisher bound to `topic`.
    /// - Throws: ``PubSubError/emptyProjectID(resource:)``,
    ///   ``PubSubError/invalidConfiguration(description:)``, or `GoogleGax.RequestError`.
    func publisher(topic: String, options: TopicPublisherOptions) throws -> any PublisherProtocol

    /// Gracefully shuts down the client's shared gRPC channel pool after awaiting
    /// outstanding work.
    ///
    /// - Parameter options: Shutdown request options.
    /// - Returns: A ``ShutdownResult``.
    /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
    func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult
  }
}

extension Clients.PublisherClientProtocol {
  /// Creates a topic-scoped publisher using the client's default topic options.
  public func publisher(topic: String) throws -> any Clients.PublisherProtocol {
    try self.publisher(topic: topic, options: .init())
  }

  /// Default unimplemented factory method throwing `GoogleGax.RequestError.unimplemented`.
  public func publisher(topic: String, options: TopicPublisherOptions) throws
    -> any Clients.PublisherProtocol
  {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Gracefully shuts down the client using default options.
  public func shutdown() async throws -> ShutdownResult {
    try await self.shutdown(options: .init())
  }

  /// Default unimplemented shutdown handler throwing `GoogleGax.RequestError.unimplemented`.
  public func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

/// Factory and shared connection-pool manager for Cloud Pub/Sub topic publishers.
///
/// Use `PublisherClient` when publishing to multiple topics in one process so all
/// topic-bound ``Publisher`` instances share a single HTTP/2 multi-channel gRPC pool,
/// authentication credentials, and retry throttler.
///
/// @Snippet(path: "PublisherQuickstart")
public final class PublisherClient: Clients.PublisherClientProtocol, Sendable {
  /// Configuration used to initialize this client.
  public let options: PublisherClientOptions

  /// Creates a new `PublisherClient`.
  ///
  /// - Parameter options: Client transport, project ID, subchannel count, and default topic options.
  /// - Throws: ``PubSubError/invalidConfiguration(description:)`` if `subchannelCount < 1` or
  ///   `defaultTopicOptions` contains invalid settings.
  public init(_ options: PublisherClientOptions = .init()) throws {
    if options.subchannelCount < 1 {
      throw PubSubError.invalidConfiguration(
        description:
          "PublisherClientOptions.subchannelCount (\(options.subchannelCount)) must be >= 1.")
    }
    try validateTopicPublisherOptions(options.defaultTopicOptions)
    self.options = options
  }

  /// Creates a topic-bound ``Publisher`` inheriting ``PublisherClientOptions/defaultTopicOptions``.
  ///
  /// - Parameter topic: Full topic resource path (`projects/{project}/topics/{topic}`) or short topic ID
  ///   when ``PublisherClientOptions/projectID`` is set.
  /// - Returns: A ``Publisher`` configured for `topic`.
  /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
  ///   ``PubSubError/invalidConfiguration(description:)``.
  public func publisher(topic: String) throws -> any Clients.PublisherProtocol {
    try self.publisher(topic: topic, options: self.options.defaultTopicOptions)
  }

  /// Creates a topic-bound ``Publisher`` sharing this client's connection pool.
  ///
  /// - Parameters:
  ///   - topic: Full topic resource path (`projects/{project}/topics/{topic}`) or short topic ID
  ///     when ``PublisherClientOptions/projectID`` is set.
  ///   - options: Topic-specific options overriding client defaults.
  /// - Returns: A ``Publisher`` configured for `topic`.
  /// - Throws: ``PubSubError/emptyProjectID(resource:)`` or
  ///   ``PubSubError/invalidConfiguration(description:)``.
  public func publisher(topic: String, options: TopicPublisherOptions) throws
    -> any Clients.PublisherProtocol
  {
    let resolvedTopic = try resolvePubSubTopicName(topic, projectID: self.options.projectID)
    try validateTopicPublisherOptions(options)
    return Publisher(resolvedTopic: resolvedTopic, options: options)
  }

  /// Gracefully shuts down the shared gRPC connection pool.
  ///
  /// @Snippet(path: "PublisherFlushAndShutdown")
  /// - Parameter options: Shutdown request options.
  /// - Returns: A ``ShutdownResult``.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult {
    ShutdownResult()
  }
}

package func resolvePubSubTopicName(_ topic: String, projectID: String?) throws -> String {
  let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw PubSubError.invalidConfiguration(description: "Topic name must not be empty.")
  }
  if !trimmed.contains("/") {
    guard let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !projectID.isEmpty
    else {
      throw PubSubError.emptyProjectID(resource: trimmed)
    }
    return "projects/\(projectID)/topics/\(trimmed)"
  }
  return trimmed
}

package func resolvePubSubSubscriptionName(
  _ subscription: String,
  projectID: String?
) throws -> String {
  let trimmed = subscription.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw PubSubError.invalidConfiguration(description: "Subscription name must not be empty.")
  }
  if !trimmed.contains("/") {
    guard let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !projectID.isEmpty
    else {
      throw PubSubError.emptyProjectID(resource: trimmed)
    }
    return "projects/\(projectID)/subscriptions/\(trimmed)"
  }
  return trimmed
}

package func validateTopicPublisherOptions(_ options: TopicPublisherOptions) throws {
  if options.batching.countThreshold < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "BatchingOptions.countThreshold (\(options.batching.countThreshold)) must be >= 1.")
  }
  if options.batching.byteThreshold < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "BatchingOptions.byteThreshold (\(options.batching.byteThreshold)) must be >= 1.")
  }
  if options.batching.delayThreshold < .zero {
    throw PubSubError.invalidConfiguration(
      description:
        "BatchingOptions.delayThreshold (\(options.batching.delayThreshold)) must be non-negative.")
  }
  if let maxPendingMessages = options.flowControl.maxPendingMessages, maxPendingMessages < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "PublisherFlowControlOptions.maxPendingMessages (\(maxPendingMessages)) must be >= 1.")
  }
  if let maxPendingBytes = options.flowControl.maxPendingBytes, maxPendingBytes < 1 {
    throw PubSubError.invalidConfiguration(
      description:
        "PublisherFlowControlOptions.maxPendingBytes (\(maxPendingBytes)) must be >= 1.")
  }
  if options.compression.bytesThreshold < 0 {
    throw PubSubError.invalidConfiguration(
      description:
        "CompressionOptions.bytesThreshold (\(options.compression.bytesThreshold)) must be >= 0.")
  }
  if options.hedging.isEnabled {
    let delay = options.hedging.delay
    if delay < .milliseconds(100) || delay > .seconds(10) {
      throw PubSubError.invalidConfiguration(
        description: "HedgingOptions.delay (\(delay)) must be between 100ms and 10s.")
    }
    let maxTokens = options.hedging.maxTokens
    if maxTokens < 1 || maxTokens > 250 {
      throw PubSubError.invalidConfiguration(
        description: "HedgingOptions.maxTokens (\(maxTokens)) must be between 1 and 250.")
    }
    let refillRatio = options.hedging.refillRatio
    if !refillRatio.isFinite || refillRatio < 0.001 || refillRatio > 0.2 {
      throw PubSubError.invalidConfiguration(
        description: "HedgingOptions.refillRatio (\(refillRatio)) must be in [0.001, 0.2].")
    }
  }
}
