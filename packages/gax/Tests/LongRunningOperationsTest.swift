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
import Synchronization
import Testing
import GoogleRpc

@testable import GoogleCloudGax

@Suite struct PollableOperationTest {
  struct MockError: Error, Equatable {
    var message: String
  }

  class MockPoller<ResponseType> {
    public var responses: [() throws -> _PollableOperationImpl<ResponseType>.State] = []
    public var pollCount = 0

    public func poll() async throws -> _PollableOperationImpl<ResponseType>.State {
      defer { pollCount += 1 }
      return try responses[pollCount]()
    }
  }

  class MockSleeper {
    public var sleepCount = 0

    public func sleep(_: Duration) async throws {
      sleepCount = sleepCount + 1
    }
  }

  static func transient() -> RequestError {
    .service(ServiceError(code: GoogleRpc.Code.unavailable, message: "UNAVAILABLE"))
  }

  static func httpError() -> RequestError {
    .http(HTTPDetails(http_status_code: 404, headers: [:]))
  }

  static func pendingState() -> _PollableOperationImpl<String>.State {
    .init(done: false, result: nil)
  }

  static func successState(_ value: String = "polling success")
    -> _PollableOperationImpl<String>.State
  {
    .init(done: true, result: .success(value))
  }

  static func errorState(_ msg: String = "error") -> _PollableOperationImpl<String>.State {
    .init(done: true, result: .failure(MockError(message: msg)))
  }

  static func pendingVoid() -> _PollableOperationImpl<Void>.State {
    .init(done: false, result: nil)
  }

  static func successVoid() -> _PollableOperationImpl<Void>.State {
    .init(done: true, result: .success(()))
  }

  @Test func initialSuccess() async throws {
    let state = Self.successState("success")
    let op: any PollableOperation<String> = _PollableOperationImpl(initialState: state) {
      return state
    }
    let res = try await op.wait()
    #expect(res == "success")
  }

  @Test func initialFailure() async throws {
    let state = Self.errorState()
    let op = _PollableOperationImpl(initialState: state) {
      return state
    }
    await #expect(throws: MockError(message: "error")) {
      try await op.wait()
    }
  }

  @Test func missingResult() async throws {
    let state = _PollableOperationImpl<String>.State(done: true, result: nil)
    let op = _PollableOperationImpl<String>(initialState: state) {
      return state
    }
    await #expect(
      throws: RequestError.malformedResponse("Operation completed but result was missing")
    ) {
      try await op.wait()
    }
  }

  @Test func waitLoopsUntilDone() async throws {
    let results = [
      { () in Self.pendingState() },
      { () in Self.successState() },
    ]
    let pollProvider = MockPoller<String>()
    pollProvider.responses = results
    let sleepProvider = MockSleeper()
    let op = _PollableOperationImpl<String>(
      initialState: Self.pendingState(),
      poll: pollProvider.poll, sleep: sleepProvider.sleep)

    let res = try await op.wait()
    #expect(res == "polling success")
    #expect(pollProvider.pollCount == 2)
    #expect(sleepProvider.sleepCount == 2)
  }

  @Test func waitLoopsFailure() async throws {
    let results = [
      { () in Self.pendingState() },
      { () in Self.pendingState() },
      { () in Self.errorState("intermediate error") },
    ]
    let pollProvider = MockPoller<String>()
    pollProvider.responses = results
    let sleepProvider = MockSleeper()
    let op = _PollableOperationImpl<String>(
      initialState: Self.pendingState(),
      poll: pollProvider.poll, sleep: sleepProvider.sleep)

    await #expect(throws: MockError(message: "intermediate error")) {
      try await op.wait()
    }
    #expect(pollProvider.pollCount == 3)
    #expect(sleepProvider.sleepCount == 3)
  }

  @Test func waitLoopsPollThrows() async throws {
    let sleepProvider = MockSleeper()
    var pollCount = 0
    let op = _PollableOperationImpl<String>(
      initialState: Self.pendingState(),
      poll: {
        pollCount += 1
        throw Self.httpError()
      },
      sleep: sleepProvider.sleep
    )

    await #expect(throws: RequestError.self) {
      try await op.wait()
    }
    #expect(pollCount == 1)
    #expect(sleepProvider.sleepCount == 1)
  }

  @Test func voidOperationPolling() async throws {
    let results = [
      { () in Self.pendingVoid() },
      { () in Self.successVoid() },
    ]
    let pollProvider = MockPoller<Void>()
    pollProvider.responses = results
    let sleepProvider = MockSleeper()
    let op = _PollableOperationImpl<Void>(
      initialState: Self.pendingVoid(),
      poll: pollProvider.poll, sleep: sleepProvider.sleep)

    try await op.wait()
    #expect(pollProvider.pollCount == 2)
    #expect(sleepProvider.sleepCount == 2)
  }

  @Test func continuesIfPolicyAllows() async throws {
    let results = [
      { () in Self.pendingState() },
      { () throws in throw Self.transient() },
      { () throws in throw Self.transient() },
      { () throws in throw Self.transient() },
      { () in Self.successState() },
    ]
    let pollProvider = MockPoller<String>()
    pollProvider.responses = results
    let sleepProvider = MockSleeper()

    let inProgressCount = Atomic<Int>(0)
    let onErrorCount = Atomic<Int>(0)
    var pollingPolicy = MockPollingPolicy()
    pollingPolicy.onError = { _, e in
      onErrorCount.add(1, ordering: .sequentiallyConsistent)
      return .retry(e)
    }
    pollingPolicy.onInProgress = { _, _ in
      inProgressCount.add(1, ordering: .sequentiallyConsistent)
    }

    let backoffPolicy = MockBackoff()

    let op = _PollableOperationImpl<String>(
      initialState: Self.pendingState(),
      poll: pollProvider.poll, sleep: sleepProvider.sleep
    )
    .withPolicies(polling: pollingPolicy, backoff: backoffPolicy)
    let res = try await op.wait()
    #expect(res == "polling success")
    #expect(inProgressCount.load(ordering: .sequentiallyConsistent) == 5)
    #expect(onErrorCount.load(ordering: .sequentiallyConsistent) == 3)
  }

  @Test func stopsIfPolicySaysSo() async throws {
    let results = [
      { () in Self.pendingState() },
      { () throws in throw Self.transient() },
      { () throws in throw Self.transient() },
    ]
    let pollProvider = MockPoller<String>()
    pollProvider.responses = results
    let sleepProvider = MockSleeper()

    let inProgressCount = Atomic<Int>(0)
    let onErrorCount = Atomic<Int>(0)
    var pollingPolicy = MockPollingPolicy()
    pollingPolicy.onError = { _, e in
      let (_, newValue) = onErrorCount.add(1, ordering: .sequentiallyConsistent)
      if newValue >= 2 {
        return .exhausted(e)
      }
      return .retry(e)
    }
    pollingPolicy.onInProgress = { _, _ in
      inProgressCount.add(1, ordering: .sequentiallyConsistent)
    }

    let backoffPolicy = MockBackoff()

    let op = _PollableOperationImpl<String>(
      initialState: Self.pendingState(),
      poll: pollProvider.poll, sleep: sleepProvider.sleep
    )
    .withPolicies(polling: pollingPolicy, backoff: backoffPolicy)
    let error = await #expect(throws: RequestError.self) {
      try await op.wait()
    }
    #expect(error == Self.transient())
    #expect(inProgressCount.load(ordering: .sequentiallyConsistent) == 3)
    #expect(onErrorCount.load(ordering: .sequentiallyConsistent) == 2)
  }
}
