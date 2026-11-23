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

/// An asynchronous single-pass pull stream of ``ReceivedMessage`` values supporting
/// deterministic shutdown.
///
/// Consume messages using Swift's `for try await` loop, and call ``stop(options:)``
/// to drain in-flight message processing or immediately nack outstanding leases.
/// Terminal stream failures (such as `NOT_FOUND` or `PERMISSION_DENIED`) are thrown
/// from the `AsyncSequence` iterator once the stream terminates.
public protocol MessageStreamProtocol: AsyncSequence, Sendable
where Element == ReceivedMessage, Failure == any Error {
  /// Stops pulling new messages and shuts down the stream cleanly.
  ///
  /// Calling `stop(options:)` multiple times is idempotent.
  ///
  /// - Parameter options: Shutdown behavior and timeout options.
  /// - Returns: A ``ShutdownResult`` indicating shutdown completed.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError`` if shutdown encounters an error.
  func stop(options: SubscriberShutdownOptions) async throws -> ShutdownResult
}

extension MessageStreamProtocol where AsyncIterator == MessageStream.AsyncIterator {
  /// Returns an unimplemented stream iterator that throws `GoogleGax.RequestError.unimplemented`.
  public func makeAsyncIterator() -> MessageStream.AsyncIterator {
    MessageStream.AsyncIterator(kind: .unimplemented)
  }
}

extension MessageStreamProtocol {
  /// Stops pulling new messages using default shutdown options.
  public func stop() async throws -> ShutdownResult {
    try await self.stop(options: .init())
  }

  /// Default unimplemented shutdown handler throwing `GoogleGax.RequestError.unimplemented`.
  public func stop(options: SubscriberShutdownOptions) async throws -> ShutdownResult {
    throw GoogleGax.RequestError.unimplemented
  }
}

/// Concrete `AsyncSequence` stream returned by ``SubscriberClient/subscribe(subscription:options:)``.
///
/// This type is single-pass: iterating once consumes the underlying stream, and subsequent
/// iterations yield `nil`. Public closure and array initializers allow test suites and
/// forwarding decorators to mock or wrap subscriber streams using plain `import GoogleCloudPubSub`.
///
/// @Snippet(path: "MessageStreamStop")
public final class MessageStream: MessageStreamProtocol, Sendable {
  /// The element yielded by this stream.
  public typealias Element = ReceivedMessage
  /// The failure type thrown by this stream.
  public typealias Failure = any Error

  /// Single-pass async iterator yielding ``ReceivedMessage`` values.
  public struct AsyncIterator: AsyncIteratorProtocol {
    /// The element type yielded by the iterator.
    public typealias Element = ReceivedMessage

    package enum Kind: Sendable {
      case stream(MessageStream)
      case session(StreamingPullSession, MessageStream)
      case finished
      case unimplemented
    }

    private let kind: Kind

    package init(kind: Kind) {
      self.kind = kind
    }

    /// Advances to and returns the next received message, or `nil` when the stream ends.
    public mutating func next() async throws -> ReceivedMessage? {
      switch self.kind {
      case .stream(let stream):
        return try await stream.nextElement()
      case .session(let session, let stream):
        guard !stream.isStopped else {
          return nil
        }
        return try await session.nextMessage()
      case .finished:
        return nil
      case .unimplemented:
        throw GoogleGax.RequestError.unimplemented
      }
    }
  }

  private enum Backing: Sendable {
    case closures(
      next: @Sendable () async throws -> ReceivedMessage?,
      onStop: @Sendable (SubscriberShutdownOptions) async throws -> ShutdownResult
    )
    case session(StreamingPullSession)
  }

  private let backing: Backing
  private let lifecycleState = Mutex((iteratorCreated: false, stopped: false))

  /// Creates a `MessageStream` backed by custom async element and shutdown handlers.
  ///
  /// Use this initializer in unit tests or forwarding decorators to simulate streaming
  /// delivery, mid-stream errors, and shutdown lifecycle transitions.
  ///
  /// - Parameters:
  ///   - next: Async closure returning the next ``ReceivedMessage``, `nil` at EOF, or throwing a stream error.
  ///   - onStop: Async closure invoked when ``stop(options:)`` is called.
  public init(
    next: @escaping @Sendable () async throws -> ReceivedMessage?,
    onStop: @escaping @Sendable (SubscriberShutdownOptions) async throws -> ShutdownResult = { _ in
      ShutdownResult()
    }
  ) {
    self.backing = .closures(next: next, onStop: onStop)
  }

  package init(session: StreamingPullSession) {
    self.backing = .session(session)
  }

  /// Creates a pre-populated finite `MessageStream` yielding `messages` followed by EOF.
  ///
  /// - Parameter messages: The messages to yield sequentially.
  public convenience init(messages: [ReceivedMessage]) {
    final class ArrayStreamBox: Sendable {
      let state = Mutex((index: 0, stopped: false))
    }
    let box = ArrayStreamBox()
    self.init(
      next: {
        box.state.withLock { state in
          guard !state.stopped, state.index < messages.count else {
            return nil
          }
          let msg = messages[state.index]
          state.index += 1
          return msg
        }
      },
      onStop: { _ in
        box.state.withLock { state in
          state.stopped = true
        }
        return ShutdownResult()
      }
    )
  }

  /// Returns an iterator over this single-pass stream.
  ///
  /// Only the first call consumes elements from the underlying stream; subsequent calls
  /// return an exhausted iterator yielding `nil`.
  public func makeAsyncIterator() -> AsyncIterator {
    let shouldStream = self.lifecycleState.withLock { state -> Bool in
      if state.iteratorCreated || state.stopped {
        return false
      }
      state.iteratorCreated = true
      return true
    }
    guard shouldStream else {
      return AsyncIterator(kind: .finished)
    }
    switch self.backing {
    case .session(let session):
      return AsyncIterator(kind: .session(session, self))
    case .closures:
      return AsyncIterator(kind: .stream(self))
    }
  }

  private var isStopped: Bool {
    self.lifecycleState.withLock { $0.stopped }
  }

  private func nextElement() async throws -> ReceivedMessage? {
    if self.isStopped {
      return nil
    }
    switch self.backing {
    case .closures(let nextImpl, _):
      return try await nextImpl()
    case .session(let session):
      return try await session.nextMessage()
    }
  }

  /// Stops pulling new messages and performs graceful drain or immediate nack per `options`.
  ///
  /// - Parameter options: Shutdown behavior and timeout configuration.
  /// - Returns: A ``ShutdownResult``.
  /// - Throws: `GoogleGax.RequestError` or ``PubSubError``.
  public func stop(options: SubscriberShutdownOptions) async throws -> ShutdownResult {
    self.lifecycleState.withLock { state in
      state.stopped = true
    }
    switch self.backing {
    case .closures(_, let stopImpl):
      return try await stopImpl(options)
    case .session(let session):
      return try await session.stop(options: options)
    }
  }
}
