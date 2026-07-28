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

/// A protocol that represents a long-running operation (LRO) which can be polled.
///
/// Long-running operations are operations that take a significant amount of time to complete.
/// This protocol defines the contract for waiting on the final result of such an operation.
public protocol PollableOperation<ResponseType> {
  /// The type of the response message returned when the long-running operation completes.
  associatedtype ResponseType

  /// Waits for the long-running operation to complete, returning the final response.
  ///
  /// - Returns: The final deserialized response of type `ResponseType`.
  /// - Throws: An error if the operation failed or if waiting was interrupted.
  func wait() async throws -> ResponseType
}

/// An internal concrete implementation of `PollableOperation` that handles polling and backoff.
///
/// This class implements a generic polling loop with a backoff policy to avoid overloading the
/// server with status requests.
public final class _PollableOperationImpl<ResponseType>: PollableOperation {
  /// Represents the current state of the long-running operation.
  public struct State {
    /// A Boolean value indicating whether the operation has finished.
    public let done: Bool
    /// The result of the operation if it is complete, or `nil` if it is still running.
    public let result: Result<ResponseType, Error>?

    /// Creates a new state representation.
    /// - Parameters:
    ///   - done: A Boolean value indicating whether the operation has finished.
    ///   - result: The result of the operation if it is complete.
    public init(done: Bool, result: Result<ResponseType, Error>?) {
      self.done = done
      self.result = result
    }
  }

  /// A closure that fetches the latest state of the operation.
  public typealias Poll = () async throws -> State

  /// A closure that suspends execution for a given duration.
  public typealias Sleep = (Duration) async throws -> Void

  private var state: State
  private let pollOp: Poll
  private let sleep: Sleep
  private var backoffPolicy: BackoffPolicy = LinearBackoffPolicy()
  private var pollingPolicy: PollingErrorPolicy = BasePollingPolicy()

  /// Initializes a new pollable operation implementation.
  ///
  /// - Parameters:
  ///   - initialState: The initial state of the operation, typically constructed from the initial response.
  ///   - poll: A closure that fetches the latest state of the operation from the server.
  ///   - sleep: A closure that suspends the current task. Defaults to using `Task.sleep(for:)`.
  public init(
    initialState: State,
    poll: @escaping Poll,
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
  ) {
    self.state = initialState
    self.pollOp = poll
    self.sleep = sleep
  }

  public func withPolicies(polling: PollingErrorPolicy, backoff: BackoffPolicy) -> Self {
    let copy = self
    copy.pollingPolicy = polling
    copy.backoffPolicy = backoff
    return copy
  }

  /// Waits for the long-running operation to complete.
  ///
  /// This method uses a simple loop that polls for the operation state at intervals determined
  /// by the backoff policy, until the operation's state reports that it is `done`.
  ///
  /// - Returns: The final deserialized response of type `ResponseType`.
  /// - Throws:
  ///   - The underlying operation error if the operation failed.
  ///   - `RequestError.malformedResponse` if the operation completed successfully but returned no result.
  public func wait() async throws -> ResponseType {
    var pollingState = PollingState()
    while !state.done {
      try pollingPolicy.onInProgress(state: pollingState)
      let delay = backoffPolicy.backoffDelay(for: pollingState.asRetryState())
      try await sleep(delay)
      pollingState.attemptCount += 1
      do {
        state = try await pollOp()
      } catch {
        let requestError = (error as? RequestError) ?? .unimplemented
        let flow = pollingPolicy.onError(state: pollingState, error: requestError)
        switch flow {
        case .permanent(let e), .exhausted(let e):
          throw e
        case .retry:
          continue
        }
      }
    }

    switch state.result {
    case .success(let response):
      return response
    case .failure(let error):
      throw error
    case .none:
      throw RequestError.malformedResponse("Operation completed but result was missing")
    }
  }
}

extension PollingState {
  func asRetryState() -> RetryState {
    RetryState(idempotent: false).with {
      $0.attemptCount = self.attemptCount
      $0.start = self.start
    }
  }
}
