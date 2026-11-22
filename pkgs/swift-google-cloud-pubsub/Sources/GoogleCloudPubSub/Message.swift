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

public import Foundation
public import GoogleWKT
import _GoogleCloudPubSubProtos

/// A Google Cloud Pub/Sub message for publishing or received from a subscription.
///
/// Use ``Message`` both to construct outbound messages for ``Publisher`` and
/// ``BlockingPublisherClient``, and to inspect payload and metadata on a
/// ``ReceivedMessage``.
///
/// Per the `google.pubsub.v1.Publish` service specification, a single published
/// message must not exceed 10 MB (`10_000_000` bytes) after protocol encoding,
/// and publish batches are limited to at most 1,000 messages and 10 MB total
/// request size.
///
/// ```swift
/// let message = Message(
///   data: Data("order-created".utf8),
///   attributes: ["source": "checkout"],
///   orderingKey: "order-123"
/// )
/// ```
public struct Message: Sendable, Hashable {
  /// The opaque message payload bytes. Empty `Data()` is permitted per the Pub/Sub protobuf schema.
  public var data: Data = Data()

  /// Application-defined string key-value attributes.
  ///
  /// Keys prefixed with `googclient_` are reserved by Google Cloud client libraries.
  /// Publishing never mutates the caller's dictionary in place.
  public var attributes: [String: String] = [:]

  /// Optional ordering key. An empty string (`""`) denotes an unordered message.
  ///
  /// Messages published with the same non-empty `orderingKey` are automatically
  /// delivered in FIFO order through per-key batches without needing an explicit
  /// opt-in setting.
  public var orderingKey: String = ""

  /// Server-assigned unique message ID (populated on received messages).
  public var messageID: String = ""

  /// Server timestamp when the message was published (populated on received messages).
  public var publishTime: GoogleWKT.WKTTimestamp? = nil

  /// Approximate 1-based delivery attempt count when a dead-letter policy is enabled (`nil` otherwise).
  public var deliveryAttempt: Int? = nil

  /// Creates an empty message.
  public init() {}

  /// Creates a message with payload data, optional attributes, and an optional ordering key.
  ///
  /// - Parameters:
  ///   - data: The message payload bytes.
  ///   - attributes: Optional string attributes associated with the message.
  ///   - orderingKey: Optional ordering key. Defaults to `""` (unordered).
  public init(
    data: Data = Data(),
    attributes: [String: String] = [:],
    orderingKey: String = ""
  ) {
    self.data = data
    self.attributes = attributes
    self.orderingKey = orderingKey
  }

  /// Creates a modified copy using closure configuration.
  ///
  /// - Parameter config: A closure that mutates a copy of this message.
  /// - Returns: The modified message copy.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

extension Message {
  package static let maxSingleMessageBytes = 10_000_000

  package func estimatedWireByteSize() -> Int {
    var size = 0
    if !self.data.isEmpty {
      size += 1 + Self.varintSize(self.data.count) + self.data.count
    }
    for (key, value) in self.attributes {
      let keyCount = key.utf8.count
      let valueCount = value.utf8.count
      let entrySize =
        (1 + Self.varintSize(keyCount) + keyCount)
        + (1 + Self.varintSize(valueCount) + valueCount)
      size += 1 + Self.varintSize(entrySize) + entrySize
    }
    if !self.orderingKey.isEmpty {
      let keyCount = self.orderingKey.utf8.count
      size += 1 + Self.varintSize(keyCount) + keyCount
    }
    return size
  }

  private static func varintSize(_ value: Int) -> Int {
    var v = UInt64(max(0, value))
    var bytes = 1
    while v >= 0x80 {
      v >>= 7
      bytes += 1
    }
    return bytes
  }

  @discardableResult
  package func validateForPublish() throws -> Int {
    if !self.orderingKey.isEmpty,
      self.orderingKey.data(using: .utf8, allowLossyConversion: false) == nil
    {
      throw PubSubError.invalidUTF8Attribute(description: "orderingKey contains invalid UTF-8")
    }
    if !self.attributes.isEmpty {
      for (key, value) in self.attributes {
        if key.data(using: .utf8, allowLossyConversion: false) == nil {
          throw PubSubError.invalidUTF8Attribute(
            description: "attribute key contains invalid UTF-8")
        }
        if value.data(using: .utf8, allowLossyConversion: false) == nil {
          throw PubSubError.invalidUTF8Attribute(
            description: "attribute value for key '\(key)' contains invalid UTF-8")
        }
      }
    }
    let encodedSize = self.estimatedWireByteSize()
    if encodedSize > Self.maxSingleMessageBytes {
      throw PubSubError.messageTooLarge(
        sizeBytes: encodedSize,
        limitBytes: Self.maxSingleMessageBytes
      )
    }
    return encodedSize
  }

  internal func toProto() -> Google_Pubsub_V1_PubsubMessage {
    var pb = Google_Pubsub_V1_PubsubMessage()
    pb.data = self.data
    pb.attributes = self.attributes
    pb.orderingKey = self.orderingKey
    return pb
  }

  /// Validates and decodes raw UTF-8 bytes into a Swift `String`.
  ///
  /// Intended for proxy and interoperability callers bridging raw byte key-value
  /// attributes across protobuf boundaries.
  @_documentation(visibility: internal)
  @_spi(GoogleCloudInternal)
  public static func _decodeValidatedUTF8(_ bytes: Data, label: String) throws -> String {
    guard let decoded = String(bytes: bytes, encoding: .utf8) else {
      throw PubSubError.invalidUTF8Attribute(description: "\(label) contains invalid UTF-8")
    }
    return decoded
  }
}
