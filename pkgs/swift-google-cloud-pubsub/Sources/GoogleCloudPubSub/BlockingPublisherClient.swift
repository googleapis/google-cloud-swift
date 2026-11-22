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

import GoogleGax

extension Clients {
  /// A Swift protocol to mock ``BlockingPublisherClient``.
  public protocol BlockingPublisherProtocol: Sendable {
    /// Immediately sends a single-message `Publish` RPC without client-side batching.
    ///
    /// - Parameters:
    ///   - message: The message to publish.
    ///   - topic: Full topic resource name or short topic ID when `projectID` is configured.
    ///   - options: Compression and request options.
    /// - Returns: A ``PublishResult`` containing the server-assigned message ID.
    /// - Throws: `GoogleGax.RequestError` for service or transport failures, or
    ///   ``PubSubError`` for local validation errors or mismatched server response counts.
    func publish(
      _ message: Message,
      topic: String,
      options: BlockingPublishOptions
    ) async throws -> PublishResult
  }
}

extension Clients.BlockingPublisherProtocol {
  /// Publishes a single message without batching using default options.
  public func publish(_ message: Message, topic: String) async throws -> PublishResult {
    try await self.publish(message, topic: topic, options: .init())
  }

  /// Default unimplemented blocking publish handler throwing `GoogleGax.RequestError.unimplemented`.
  public func publish(
    _ message: Message,
    topic: String,
    options: BlockingPublishOptions
  ) async throws -> PublishResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

/// Unbatched single-message publisher for serverless workloads or low-throughput callers
/// that prefer direct per-message RPC latency without background batching tasks.
///
/// `BlockingPublisherClient` shares a gRPC channel pool and supports retries, custom headers,
/// `PUBSUB_EMULATOR_HOST`, `10 MB` message-size guards, and optional `gzip` payload compression.
///
/// @Snippet(path: "BlockingPublisherPublish")
public final class BlockingPublisherClient: Clients.BlockingPublisherProtocol, Sendable {
  /// Client configuration used to initialize this instance.
  public let options: BlockingPublisherClientOptions

  /// Creates a new `BlockingPublisherClient`.
  ///
  /// - Parameter options: Transport, credentials, project ID, subchannels, and default compression.
  /// - Throws: ``PubSubError/invalidConfiguration(description:)`` if client options are malformed.
  public init(_ options: BlockingPublisherClientOptions = .init()) throws {
    if options.subchannelCount < 1 {
      throw PubSubError.invalidConfiguration(
        description:
          "BlockingPublisherClientOptions.subchannelCount (\(options.subchannelCount)) must be >= 1."
      )
    }
    if options.compression.bytesThreshold < 0 {
      throw PubSubError.invalidConfiguration(
        description:
          "CompressionOptions.bytesThreshold (\(options.compression.bytesThreshold)) must be >= 0."
      )
    }
    self.options = options
  }

  /// Publishes `message` immediately to `topic` via unary `google.pubsub.v1.Publisher/Publish`.
  ///
  /// @Snippet(path: "BlockingPublisherPublish")
  /// - Parameters:
  ///   - message: The message to publish.
  ///   - topic: Full topic resource name or short topic ID when `projectID` is configured.
  ///   - options: Per-call compression and request options.
  /// - Returns: A ``PublishResult`` containing the server-assigned message ID.
  /// - Throws: `GoogleGax.RequestError` for service or transport failures, or ``PubSubError``
  ///   for invalid configuration, invalid UTF-8 metadata, or `> 10_000_000`-byte payloads.
  public func publish(
    _ message: Message,
    topic: String,
    options: BlockingPublishOptions
  ) async throws -> PublishResult {
    throw GoogleGax.RequestError.unimplemented
  }
}
