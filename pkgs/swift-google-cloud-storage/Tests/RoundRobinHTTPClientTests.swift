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

import AsyncHTTPClient
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import NIOCore
import NIOHTTP1
import Synchronization
import Testing

private struct RoundRobinTestError: Error, Sendable, Equatable {}

private final class HistoryRecorder: Sendable {
  private let entries = Mutex<[Int]>([])

  func append(_ slotIndex: Int) {
    self.entries.withLock { $0.append(slotIndex) }
  }

  var values: [Int] {
    self.entries.withLock { $0 }
  }
}

private final class RecordingSlotHTTPClient: _HTTPClientProtocol, Sendable {
  let slotIndex: Int
  let shouldThrow: Bool
  private let callCount = Atomic<Int>(0)
  private let history: HistoryRecorder

  init(slotIndex: Int, shouldThrow: Bool = false, history: HistoryRecorder) {
    self.slotIndex = slotIndex
    self.shouldThrow = shouldThrow
    self.history = history
  }

  var calls: Int {
    self.callCount.load(ordering: .acquiring)
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    self.callCount.add(1, ordering: .relaxed)
    self.history.append(self.slotIndex)
    if self.shouldThrow {
      throw RoundRobinTestError()
    }
    return HTTPClientResponse(
      status: .ok,
      body: .bytes(ByteBuffer(string: "slot-\(self.slotIndex)"))
    )
  }
}

@Suite struct RoundRobinHTTPClientTests {
  @Test func singleClientRoutesAllRequestsToSlotZero() async throws {
    let history = HistoryRecorder()
    let slot0 = RecordingSlotHTTPClient(slotIndex: 0, history: history)
    let pool = RoundRobinHTTPClient(clients: [slot0])

    for i in 0..<5 {
      let response = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com/\(i)"),
        timeout: .seconds(5)
      )
      var buffer = ByteBuffer()
      for try await chunk in response.body {
        var copy = chunk
        buffer.writeBuffer(&copy)
      }
      #expect(String(buffer: buffer) == "slot-0")
    }

    #expect(slot0.calls == 5)
    #expect(history.values == [0, 0, 0, 0, 0])
  }

  @Test func distributesSequentiallyAndWrapsAround() async throws {
    let history = HistoryRecorder()
    let slots = (0..<3).map { RecordingSlotHTTPClient(slotIndex: $0, history: history) }
    let pool = RoundRobinHTTPClient(clients: slots)

    for i in 0..<7 {
      _ = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com/\(i)"),
        timeout: .seconds(5)
      )
    }

    #expect(slots.map(\.calls) == [3, 2, 2])
    #expect(history.values == [0, 1, 2, 0, 1, 2, 0])
  }

  @Test func continuesAdvancingAfterPreHeaderFailure() async throws {
    let history = HistoryRecorder()
    let slots = [
      RecordingSlotHTTPClient(slotIndex: 0, shouldThrow: false, history: history),
      RecordingSlotHTTPClient(slotIndex: 1, shouldThrow: true, history: history),
      RecordingSlotHTTPClient(slotIndex: 2, shouldThrow: false, history: history),
    ]
    let pool = RoundRobinHTTPClient(clients: slots)

    _ = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/0"),
      timeout: .seconds(5)
    )
    await #expect(throws: RoundRobinTestError.self) {
      _ = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com/1"),
        timeout: .seconds(5)
      )
    }
    _ = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/2"),
      timeout: .seconds(5)
    )
    _ = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/3"),
      timeout: .seconds(5)
    )

    #expect(slots.map(\.calls) == [2, 1, 1])
    #expect(history.values == [0, 1, 2, 0])
  }

  @Test func concurrentRequestsDistributeEvenly() async throws {
    let history = HistoryRecorder()
    let slots = (0..<3).map { RecordingSlotHTTPClient(slotIndex: $0, history: history) }
    let pool = RoundRobinHTTPClient(clients: slots)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<90 {
        group.addTask {
          _ = try await pool.execute(
            request: HTTPClientRequest(url: "https://example.com/\(i)"),
            timeout: .seconds(5)
          )
        }
      }
      try await group.waitForAll()
    }

    #expect(slots.map(\.calls) == [30, 30, 30])
  }
}
