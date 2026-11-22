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

/// The terminal settlement outcome for an acknowledgment or negative acknowledgment.
///
/// - Note: Adding cases to this enumeration is not considered a breaking change.
///   Future releases may promote values out of ``other(_:)`` into dedicated cases.
///   Do not match specific strings inside `.other(_:)`; always include an
///   `@unknown default:` clause when switching over this type.
public enum SettlementStatus: Sendable, Hashable {
  /// The settlement succeeded (or mapped from fire-and-forget at-least-once RPC success).
  case success
  /// The caller lacks permission (`pubsub.subscriptions.consume`) to settle the message.
  case permissionDenied
  /// The subscription's precondition prevented settlement (for example, detached or mismatched state).
  case failedPrecondition
  /// The acknowledgment ID is invalid or expired (past the 10-minute server ack-ID TTL).
  case invalidAckID
  /// An unrecognized permanent failure reason returned by the server.
  case other(String)
}

/// Detailed failure metadata for a confirmed exactly-once settlement
/// (`ackWithResult` or `nackWithResult`).
public struct AckError: Error, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The classified terminal settlement status.
  public var status: SettlementStatus

  /// A human-readable diagnostic description of the failure.
  public var message: String

  /// The underlying `GoogleGax.RequestError` returned by the RPC layer, if any.
  public var underlyingError: GoogleGax.RequestError?

  /// Creates an acknowledgment failure value.
  ///
  /// - Parameters:
  ///   - status: The terminal settlement status.
  ///   - message: A human-readable failure description.
  ///   - underlyingError: Optional underlying RPC or transport error.
  public init(
    status: SettlementStatus,
    message: String,
    underlyingError: GoogleGax.RequestError? = nil
  ) {
    self.status = status
    self.message = message
    self.underlyingError = underlyingError
  }

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }

  /// Human-readable description of the settlement failure.
  public var description: String {
    "AckError(\(self.status)): \(self.message)"
  }

  /// Detailed diagnostic representation including status, message, and underlying error.
  public var debugDescription: String {
    "AckError(status: \(self.status), message: \(String(reflecting: self.message)), underlyingError: \(String(describing: self.underlyingError)))"
  }
}

/// Reason a local publish flow-control limit was exceeded.
///
/// - Note: Adding cases to this enumeration is not considered a breaking change.
///   Always include an `@unknown default:` clause when switching over this type.
public enum FlowControlLimitReason: Sendable, Equatable {
  /// Pending message count would exceed the configured limit.
  case messageCount(pending: Int, limit: Int)
  /// Pending byte count would exceed the configured limit.
  case byteCount(pendingBytes: Int, limitBytes: Int)
}

/// Client-detected errors thrown by `GoogleCloudPubSub`.
///
/// ### Error Contract
/// - **Service and transport failures:** Network, authentication, gRPC status, and
///   exhausted retry-loop errors from `Publish`, `Pull`, `StreamingPull`,
///   `Acknowledge`, and `ModifyAckDeadline` are thrown as `GoogleGax.RequestError`
///   (such as `.service`, `.io`, `.exhausted`, `.http`, `.binding`, `.malformedResponse`,
///   `.badURL`, and `.unimplemented`).
/// - **Client-detected and lifecycle failures:** Local structural invariant
///   violations, shutdown states, corked ordering keys, and confirmed settlement
///   failures throw ``PubSubError``.
///
/// - Note: New cases may be added in minor or patch releases; always include an
///   `@unknown default:` clause when switching over this enumeration.
public enum PubSubError: Error, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The publisher (or parent ``PublisherClient``) has already been shut down.
  case publisherShutDown
  /// The message's ordering key is paused due to an earlier permanent failure.
  case orderingKeyPaused(orderingKey: String)
  /// A single message exceeds the `10_000_000`-byte (`10 MB`) wire limit.
  case messageTooLarge(sizeBytes: Int, limitBytes: Int)
  /// Message attribute keys or values (or ordering key) are not valid UTF-8.
  case invalidUTF8Attribute(description: String)
  /// Local publish flow-control limits were exceeded with ``FlowControlLimitExceededBehavior/signalError``.
  case flowControlLimitExceeded(FlowControlLimitReason)
  /// A short resource ID was passed without a configured `projectID`.
  case emptyProjectID(resource: String)
  /// Server `PublishResponse.message_ids` count did not match request `messages` count.
  case mismatchedMessageIDCount(expected: Int, received: Int)
  /// Confirmed exactly-once settlement (`ackWithResult` / `nackWithResult`) failed.
  case settlementFailed(AckError)
  /// Client, topic publisher, or subscriber options contain an invalid setting.
  case invalidConfiguration(description: String)

  /// Human-readable description of this error.
  public var description: String {
    switch self {
    case .publisherShutDown:
      return "Publisher has already been shut down."
    case .orderingKeyPaused(let orderingKey):
      return
        "Ordering key '\(orderingKey)' is paused; call resumePublishing(orderingKey:) to resume."
    case .messageTooLarge(let sizeBytes, let limitBytes):
      return "Message encoded size (\(sizeBytes) bytes) exceeds limit (\(limitBytes) bytes)."
    case .invalidUTF8Attribute(let description):
      return "Invalid UTF-8 message metadata: \(description)"
    case .flowControlLimitExceeded(let reason):
      switch reason {
      case .messageCount(let pending, let limit):
        return "Publish flow control limit exceeded: \(pending) pending messages (limit: \(limit))."
      case .byteCount(let pendingBytes, let limitBytes):
        return
          "Publish flow control limit exceeded: \(pendingBytes) pending bytes (limit: \(limitBytes))."
      }
    case .emptyProjectID(let resource):
      return "Cannot expand short resource '\(resource)' without a non-empty projectID."
    case .mismatchedMessageIDCount(let expected, let received):
      return "Server returned \(received) message IDs for batch of \(expected) messages."
    case .settlementFailed(let error):
      return error.description
    case .invalidConfiguration(let description):
      return "Invalid Pub/Sub configuration: \(description)"
    }
  }

  /// Detailed diagnostic representation naming the error case and its description.
  public var debugDescription: String {
    let caseName: String
    switch self {
    case .publisherShutDown:
      caseName = "publisherShutDown"
    case .orderingKeyPaused(let orderingKey):
      caseName = "orderingKeyPaused(orderingKey: \(String(reflecting: orderingKey)))"
    case .messageTooLarge(let sizeBytes, let limitBytes):
      caseName = "messageTooLarge(sizeBytes: \(sizeBytes), limitBytes: \(limitBytes))"
    case .invalidUTF8Attribute(let description):
      caseName = "invalidUTF8Attribute(description: \(String(reflecting: description)))"
    case .flowControlLimitExceeded(let reason):
      caseName = "flowControlLimitExceeded(\(reason))"
    case .emptyProjectID(let resource):
      caseName = "emptyProjectID(resource: \(String(reflecting: resource)))"
    case .mismatchedMessageIDCount(let expected, let received):
      caseName = "mismatchedMessageIDCount(expected: \(expected), received: \(received))"
    case .settlementFailed(let error):
      caseName = "settlementFailed(\(error.debugDescription))"
    case .invalidConfiguration(let description):
      caseName = "invalidConfiguration(description: \(String(reflecting: description)))"
    }
    return "PubSubError.\(caseName): \(self.description)"
  }
}
