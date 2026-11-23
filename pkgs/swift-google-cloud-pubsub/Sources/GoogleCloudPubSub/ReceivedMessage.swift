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
import Synchronization

/// Protocol handling message acknowledgment and negative acknowledgment.
///
/// Implement this protocol directly in unit tests to capture settlement calls or
/// simulate exactly-once settlement errors without mocking gRPC connections.
public protocol AckHandlerProtocol: Sendable {
  /// Schedules an asynchronous fire-and-forget acknowledgment (`Acknowledge`).
  ///
  /// - Parameter options: Acknowledgment options.
  /// - Returns: An ``AckQueuedResult`` handle representing the queued settlement.
  @discardableResult
  func ack(options: AckOptions) -> AckQueuedResult

  /// Schedules an asynchronous fire-and-forget negative acknowledgment (`ModifyAckDeadline(..., 0)`).
  ///
  /// - Parameter options: Negative acknowledgment options.
  /// - Returns: A ``NackQueuedResult`` handle representing the queued settlement.
  @discardableResult
  func nack(options: NackOptions) -> NackQueuedResult

  /// Acknowledges the message and awaits confirmation from Cloud Pub/Sub.
  ///
  /// On exactly-once delivery subscriptions, this method retries transient settlement
  /// errors and throws ``PubSubError/settlementFailed(_:)`` on permanent errors
  /// (`permissionDenied`, `failedPrecondition`, `invalidAckID`). On standard
  /// at-least-once subscriptions, it returns ``AckResult`` (`.success`) once the
  /// underlying RPC completes.
  ///
  /// - Parameter options: Acknowledgment options.
  /// - Returns: The confirmed ``AckResult``.
  /// - Throws: ``PubSubError/settlementFailed(_:)`` on permanent exactly-once rejection,
  ///   or `GoogleGax.RequestError` on transport/unimplemented failures.
  func ackWithResult(options: AckOptions) async throws -> AckResult

  /// Negatively acknowledges the message and awaits confirmation from Cloud Pub/Sub.
  ///
  /// - Parameter options: Negative acknowledgment options.
  /// - Returns: The confirmed ``AckResult``.
  /// - Throws: ``PubSubError/settlementFailed(_:)`` on permanent exactly-once rejection,
  ///   or `GoogleGax.RequestError` on transport/unimplemented failures.
  func nackWithResult(options: NackOptions) async throws -> AckResult
}

extension AckHandlerProtocol {
  /// Schedules a fire-and-forget acknowledgment using default options.
  @discardableResult
  public func ack() -> AckQueuedResult {
    self.ack(options: .init())
  }

  /// Default unimplemented acknowledgment handler returning an empty ``AckQueuedResult``.
  @discardableResult
  public func ack(options: AckOptions) -> AckQueuedResult {
    AckQueuedResult()
  }

  /// Schedules a fire-and-forget negative acknowledgment using default options.
  @discardableResult
  public func nack() -> NackQueuedResult {
    self.nack(options: .init())
  }

  /// Default unimplemented negative acknowledgment handler returning an empty ``NackQueuedResult``.
  @discardableResult
  public func nack(options: NackOptions) -> NackQueuedResult {
    NackQueuedResult()
  }

  /// Acknowledges the message with default options and awaits confirmation.
  public func ackWithResult() async throws -> AckResult {
    try await self.ackWithResult(options: .init())
  }

  /// Default unimplemented confirmed acknowledgment throwing `GoogleGax.RequestError.unimplemented`.
  public func ackWithResult(options: AckOptions) async throws -> AckResult {
    throw GoogleGax.RequestError.unimplemented
  }

  /// Negatively acknowledges the message with default options and awaits confirmation.
  public func nackWithResult() async throws -> AckResult {
    try await self.nackWithResult(options: .init())
  }

  /// Default unimplemented confirmed negative acknowledgment throwing `GoogleGax.RequestError.unimplemented`.
  public func nackWithResult(options: NackOptions) async throws -> AckResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

package enum PermitReleaseTarget: Sendable {
  case none
  case flowGate(SubscriberFlowGate, bytes: Int)
  case closure(@Sendable () -> Void)

  fileprivate func release() {
    switch self {
    case .none:
      break
    case .flowGate(let gate, let bytes):
      gate.release(bytes: bytes)
    case .closure(let callback):
      callback()
    }
  }
}

package final class LeaseTracker: Sendable {
  private enum BackingAckTarget: Sendable {
    case leaseManager(LeaseManager, ackID: String, isExactlyOnce: Bool)
    case handler(any AckHandlerProtocol)
  }

  private struct State: Sendable {
    var settled: Bool = false
    var expired: Bool = false
  }

  private let state: Mutex<State> = Mutex(State())
  private let backing: BackingAckTarget
  private let releaseTarget: PermitReleaseTarget

  package init(
    handler: any AckHandlerProtocol,
    onPermitRelease: (@Sendable () -> Void)? = nil
  ) {
    self.backing = .handler(handler)
    self.releaseTarget = onPermitRelease.map(PermitReleaseTarget.closure) ?? .none
  }

  package init(
    leaseManager: LeaseManager,
    ackID: String,
    isExactlyOnce: Bool,
    releaseTarget: PermitReleaseTarget
  ) {
    self.backing = .leaseManager(leaseManager, ackID: ackID, isExactlyOnce: isExactlyOnce)
    self.releaseTarget = releaseTarget
  }

  /// Atomically marks the message settled and invokes permit release once (if not already expired).
  @discardableResult
  package func markSettled() -> Bool {
    let shouldRelease = self.state.withLock { state -> Bool in
      if state.settled {
        return false
      }
      state.settled = true
      return !state.expired
    }
    if shouldRelease {
      self.releaseTarget.release()
    }
    return shouldRelease
  }

  /// Marks the local lease expired (past `maxExtension`) without issuing `Nack(0)` on `deinit`,
  /// while releasing flow-control permits once.
  package func markExpired() {
    let shouldRelease = self.state.withLock { state -> Bool in
      if state.settled || state.expired {
        return false
      }
      state.expired = true
      return true
    }
    if shouldRelease {
      self.releaseTarget.release()
    }
  }

  package func ack(options: AckOptions) -> AckQueuedResult {
    self.markSettled()
    switch self.backing {
    case .leaseManager(let manager, let ackID, let isExactlyOnce):
      manager.ack(ackID: ackID, isExactlyOnce: isExactlyOnce, options: options)
      return AckQueuedResult()
    case .handler(let handler):
      return handler.ack(options: options)
    }
  }

  package func nack(options: NackOptions) -> NackQueuedResult {
    self.markSettled()
    switch self.backing {
    case .leaseManager(let manager, let ackID, let isExactlyOnce):
      manager.nack(ackID: ackID, isExactlyOnce: isExactlyOnce, options: options)
      return NackQueuedResult()
    case .handler(let handler):
      return handler.nack(options: options)
    }
  }

  package func ackWithResult(options: AckOptions) async throws -> AckResult {
    self.markSettled()
    switch self.backing {
    case .leaseManager(let manager, let ackID, let isExactlyOnce):
      return try await manager.ackWithResult(
        ackID: ackID, isExactlyOnce: isExactlyOnce, options: options)
    case .handler(let handler):
      return try await handler.ackWithResult(options: options)
    }
  }

  package func nackWithResult(options: NackOptions) async throws -> AckResult {
    self.markSettled()
    switch self.backing {
    case .leaseManager(let manager, let ackID, let isExactlyOnce):
      return try await manager.nackWithResult(
        ackID: ackID, isExactlyOnce: isExactlyOnce, options: options)
    case .handler(let handler):
      return try await handler.nackWithResult(options: options)
    }
  }

  deinit {
    let shouldAutoNack = self.state.withLock { state -> Bool in
      if state.settled || state.expired {
        return false
      }
      state.settled = true
      return true
    }
    if shouldAutoNack {
      switch self.backing {
      case .leaseManager(let manager, let ackID, let isExactlyOnce):
        manager.nack(ackID: ackID, isExactlyOnce: isExactlyOnce, options: .init())
      case .handler(let handler):
        _ = handler.nack(options: .init())
      }
      self.releaseTarget.release()
    }
  }
}

private struct TrackedAckHandler: AckHandlerProtocol, Sendable {
  let leaseTracker: LeaseTracker

  func ack(options: AckOptions) -> AckQueuedResult {
    self.leaseTracker.ack(options: options)
  }

  func nack(options: NackOptions) -> NackQueuedResult {
    self.leaseTracker.nack(options: options)
  }

  func ackWithResult(options: AckOptions) async throws -> AckResult {
    try await self.leaseTracker.ackWithResult(options: options)
  }

  func nackWithResult(options: NackOptions) async throws -> AckResult {
    try await self.leaseTracker.nackWithResult(options: options)
  }
}

/// A message delivered from a Cloud Pub/Sub subscription along with its settlement handle.
///
/// Always settle a ``ReceivedMessage`` using ``ack(options:)``, ``nack(options:)``,
/// ``ackWithResult(options:)``, or ``nackWithResult(options:)``. If all copies of
/// a ``ReceivedMessage`` are deallocated without an explicit settlement (and before
/// its `maxExtension` expires), the library automatically negatively acknowledges the
/// message so it can be promptly redelivered.
///
/// ```swift
/// for try await received in stream {
///   process(received.message)
///   received.ack()
/// }
/// ```
public struct ReceivedMessage: Sendable {
  /// The delivered message payload, attributes, ordering key, and metadata.
  public let message: Message

  /// Whether the subscription batch indicated exactly-once delivery was enabled at receipt time.
  public let isExactlyOnce: Bool

  /// Settlement handler synchronized with this message's automatic lease-release and auto-nack tracker.
  ///
  /// Settling through `ackHandler` marks this message settled (preventing duplicate `deinit` nacks),
  /// and retaining `ackHandler` inside a forwarding wrapper preserves automatic `deinit` nack transfer.
  public var ackHandler: any AckHandlerProtocol {
    TrackedAckHandler(leaseTracker: self.leaseTracker)
  }

  private let leaseTracker: LeaseTracker

  /// Creates a `ReceivedMessage` for unit tests and forwarding decorators.
  ///
  /// - Parameters:
  ///   - message: The delivered message data and metadata.
  ///   - isExactlyOnce: Whether exactly-once delivery semantics are active. Defaults to `false`.
  ///   - ackHandler: The handler receiving `ack` / `nack` calls (including automatic `deinit` nack).
  public init(
    message: Message,
    isExactlyOnce: Bool = false,
    ackHandler: any AckHandlerProtocol
  ) {
    self.message = message
    self.isExactlyOnce = isExactlyOnce
    self.leaseTracker = LeaseTracker(handler: ackHandler)
  }

  package init(
    message: Message,
    isExactlyOnce: Bool,
    leaseTracker: LeaseTracker
  ) {
    self.message = message
    self.isExactlyOnce = isExactlyOnce
    self.leaseTracker = leaseTracker
  }

  /// Schedules a fire-and-forget acknowledgment.
  ///
  /// - Parameter options: Acknowledgment options.
  /// - Returns: An ``AckQueuedResult`` handle.
  @discardableResult
  public func ack(options: AckOptions = .init()) -> AckQueuedResult {
    self.leaseTracker.ack(options: options)
  }

  /// Schedules a fire-and-forget negative acknowledgment, requesting immediate redelivery.
  ///
  /// - Parameter options: Negative acknowledgment options.
  /// - Returns: A ``NackQueuedResult`` handle.
  @discardableResult
  public func nack(options: NackOptions = .init()) -> NackQueuedResult {
    self.leaseTracker.nack(options: options)
  }

  /// Acknowledges the message and awaits confirmation.
  ///
  /// - Parameter options: Acknowledgment options.
  /// - Returns: The confirmed ``AckResult``.
  /// - Throws: ``PubSubError/settlementFailed(_:)`` or `GoogleGax.RequestError`.
  public func ackWithResult(options: AckOptions = .init()) async throws -> AckResult {
    try await self.leaseTracker.ackWithResult(options: options)
  }

  /// Negatively acknowledges the message and awaits confirmation.
  ///
  /// - Parameter options: Negative acknowledgment options.
  /// - Returns: The confirmed ``AckResult``.
  /// - Throws: ``PubSubError/settlementFailed(_:)`` or `GoogleGax.RequestError`.
  public func nackWithResult(options: NackOptions = .init()) async throws -> AckResult {
    try await self.leaseTracker.nackWithResult(options: options)
  }

  package func cancelAutoNackAndRelease() {
    _ = self.leaseTracker.markSettled()
  }
}
