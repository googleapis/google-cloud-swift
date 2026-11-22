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

/// The result of publishing a single message.
public struct PublishResult: Sendable, Equatable {
  /// The server-assigned unique message identifier.
  public var messageID: String = ""

  /// Creates a publish result with the given server-assigned message identifier.
  ///
  /// - Parameter messageID: The server-assigned message ID. Defaults to `""`.
  public init(messageID: String = "") {
    self.messageID = messageID
  }

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result returned when scheduling a fire-and-forget acknowledgment (`ack`).
public struct AckQueuedResult: Sendable, Equatable {
  /// Creates an acknowledgment queued result.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result returned when scheduling a fire-and-forget negative acknowledgment (`nack`).
public struct NackQueuedResult: Sendable, Equatable {
  /// Creates a negative acknowledgment queued result.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result returned by ``AckHandlerProtocol/ackWithResult(options:)`` or
/// ``AckHandlerProtocol/nackWithResult(options:)``.
public struct AckResult: Sendable, Equatable {
  /// The terminal status of the settlement operation.
  public var status: SettlementStatus = .success

  /// Creates a settlement result.
  ///
  /// - Parameter status: The terminal settlement status. Defaults to `.success`.
  public init(status: SettlementStatus = .success) {
    self.status = status
  }

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result of flushing buffered batches on a ``Publisher``.
public struct FlushResult: Sendable, Equatable {
  /// Creates a flush result.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result of resuming a paused ordering key.
public struct ResumePublishingResult: Sendable, Equatable {
  /// Creates a resume-publishing result.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result of shutting down a publisher, publisher client, or subscriber stream.
public struct ShutdownResult: Sendable, Equatable {
  /// Creates a shutdown result.
  public init() {}

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}

/// The result of a managed unary pull via ``SubscriberClient/pull(subscription:options:)``.
public struct PullResult: Sendable {
  /// Messages received from the subscription, each enrolled in lease management.
  public var messages: [ReceivedMessage] = []

  /// Creates a pull result.
  ///
  /// - Parameter messages: The pulled messages.
  public init(messages: [ReceivedMessage] = []) {
    self.messages = messages
  }

  /// Creates a modified copy using closure configuration.
  @inlinable
  public func with(_ config: (inout Self) throws -> Void) rethrows -> Self {
    var copy = self
    try config(&copy)
    return copy
  }
}
