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

import Synchronization

package final class BatchPublishBox: Sendable {
  private struct Waiter: Sendable {
    let id: UInt64
    let index: Int
    let continuation: CheckedContinuation<PublishResult, any Error>
  }

  private enum Status: Sendable {
    case pending(nextID: UInt64, waiters: [Waiter])
    case resolved([String])
    case failed(any Error)
  }

  private let status = Mutex<Status>(.pending(nextID: 1, waiters: []))

  package init() {}

  package func resolveSuccess(_ messageIDs: [String]) {
    let waitersToResume = self.status.withLock { status -> [Waiter] in
      guard case .pending(_, let waiters) = status else {
        return []
      }
      status = .resolved(messageIDs)
      return waiters
    }
    for waiter in waitersToResume {
      waiter.continuation.resume(returning: PublishResult(messageID: messageIDs[waiter.index]))
    }
  }

  package func resolveFailure(_ error: any Error) {
    let waitersToResume = self.status.withLock { status -> [Waiter] in
      guard case .pending(_, let waiters) = status else {
        return []
      }
      status = .failed(error)
      return waiters
    }
    for waiter in waitersToResume {
      waiter.continuation.resume(throwing: error)
    }
  }

  func result(at index: Int) async throws -> PublishResult {
    try Task.checkCancellation()
    let fast: Result<PublishResult, any Error>? = self.status.withLock { status in
      switch status {
      case .resolved(let ids):
        return .success(PublishResult(messageID: ids[index]))
      case .failed(let error):
        return .failure(error)
      case .pending:
        return nil
      }
    }
    if let fast {
      return try fast.get()
    }

    final class CancelBox: Sendable {
      struct CancelState: Sendable {
        var waiterID: UInt64?
        var cancelled: Bool = false
      }
      let state = Mutex(CancelState())
    }
    let cancelBox = CancelBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<PublishResult, any Error>) in
        let immediate: Result<PublishResult, any Error>? = self.status.withLock { status in
          switch status {
          case .resolved(let ids):
            return .success(PublishResult(messageID: ids[index]))
          case .failed(let error):
            return .failure(error)
          case .pending(let nextID, var waiters):
            let shouldCancel = cancelBox.state.withLock { cs -> Bool in
              if cs.cancelled || Task.isCancelled {
                cs.cancelled = true
                return true
              }
              cs.waiterID = nextID
              return false
            }
            if shouldCancel {
              return .failure(CancellationError())
            }
            waiters.append(Waiter(id: nextID, index: index, continuation: continuation))
            status = .pending(nextID: nextID + 1, waiters: waiters)
            return nil
          }
        }
        if let immediate {
          continuation.resume(with: immediate)
        }
      }
    } onCancel: {
      let waiterID = cancelBox.state.withLock { cs -> UInt64? in
        cs.cancelled = true
        return cs.waiterID
      }
      guard let waiterID else {
        return
      }
      let cancelledContinuation = self.status.withLock {
        status -> CheckedContinuation<PublishResult, any Error>? in
        guard case .pending(let nextID, var waiters) = status else {
          return nil
        }
        guard let idx = waiters.firstIndex(where: { $0.id == waiterID }) else {
          return nil
        }
        let entry = waiters.remove(at: idx)
        status = .pending(nextID: nextID, waiters: waiters)
        return entry.continuation
      }
      cancelledContinuation?.resume(throwing: CancellationError())
    }
  }
}

/// An opaque handle representing an accepted, in-flight publish operation.
///
/// Dropping or ignoring a ``PublishHandle`` never cancels transmission of the
/// accepted message. Call ``result()`` to await the server-assigned message ID
/// or inspect terminal publish failures.
public struct PublishHandle: Sendable {
  private enum Kind: Sendable {
    case closure(@Sendable () async throws -> PublishResult)
    case batch(BatchPublishBox, index: Int)
  }

  private let kind: Kind

  /// Awaits the publish outcome and returns the server-assigned message ID.
  ///
  /// - Returns: A ``PublishResult`` containing the server-assigned ``PublishResult/messageID``.
  /// - Throws: `GoogleGax.RequestError` for service or transport failures, or
  ///   ``PubSubError`` for local validation or ordering-key lifecycle failures.
  public func result() async throws -> PublishResult {
    switch self.kind {
    case .closure(let resolver):
      return try await resolver()
    case .batch(let box, let index):
      return try await box.result(at: index)
    }
  }

  package init(batchBox: BatchPublishBox, index: Int) {
    self.kind = .batch(batchBox, index: index)
  }

  /// Creates a pre-resolved handle for unit tests and mock implementations.
  ///
  /// - Parameter resolvedResult: The immediate result to yield when ``result()`` is awaited.
  public init(resolvedResult: Result<PublishResult, any Error>) {
    self.kind = .closure {
      try resolvedResult.get()
    }
  }

  /// Creates a handle backed by a custom async resolver for unit tests and forwarding decorators.
  ///
  /// - Parameter resolver: An async closure invoked to resolve the publish result.
  public init(resolver: @escaping @Sendable () async throws -> PublishResult) {
    self.kind = .closure(resolver)
  }
}
