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
import Foundation
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import NIOCore
import NIOHTTP1
import Synchronization
import Testing

private struct P2CTestError: Error, Sendable, Equatable {}

private final class StubHTTPClient: _HTTPClientProtocol, Sendable {
  typealias Handler = @Sendable (HTTPClientRequest, Duration) async throws -> HTTPClientResponse

  private let handler: Handler
  private let callCount = Atomic<Int>(0)

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  var calls: Int {
    self.callCount.load(ordering: .acquiring)
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    self.callCount.add(1, ordering: .relaxed)
    return try await self.handler(request, timeout)
  }
}

private actor StreamGate {
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var isReleased = false

  func wait() async {
    if self.isReleased {
      return
    }
    await withCheckedContinuation { continuation in
      if self.isReleased {
        continuation.resume()
      } else {
        self.continuations.append(continuation)
      }
    }
  }

  func release() {
    self.isReleased = true
    let pending = self.continuations
    self.continuations.removeAll(keepingCapacity: false)
    for continuation in pending {
      continuation.resume()
    }
  }
}

@Suite struct P2CHTTPClientTests {
  @Test(arguments: [
    (coreCount: 0, expected: 1),
    (coreCount: 1, expected: 1),
    (coreCount: 2, expected: 1),
    (coreCount: 3, expected: 1),
    (coreCount: 4, expected: 2),
    (coreCount: 7, expected: 2),
    (coreCount: 8, expected: 3),
    (coreCount: 16, expected: 4),
    (coreCount: 64, expected: 6),
    (coreCount: 192, expected: 7),
  ])
  func resolveConnectionPoolSizeDefaults(coreCount: Int, expected: Int) {
    #expect(StorageClientOptions.resolveConnectionPoolSize(nil, coreCount: coreCount) == expected)
  }

  @Test(arguments: [
    (configured: -5, expected: 1),
    (configured: 0, expected: 1),
    (configured: 1, expected: 1),
    (configured: 3, expected: 3),
    (configured: 32, expected: 32),
  ])
  func resolveConnectionPoolSizeOverridesAndClamping(configured: Int, expected: Int) {
    #expect(
      StorageClientOptions.resolveConnectionPoolSize(configured, coreCount: 8) == expected
    )
  }

  @Test func singleClientAlwaysRoutesToSlotZero() async throws {
    let client = StubHTTPClient { _, _ in
      HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: "ok")))
    }
    let pool = P2CHTTPClient(clients: [client], seed: 1)

    for _ in 0..<4 {
      let response = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com"),
        timeout: .seconds(5)
      )
      var collected = ByteBuffer()
      for try await chunk in response.body {
        var copy = chunk
        collected.writeBuffer(&copy)
      }
      #expect(String(buffer: collected) == "ok")
    }

    #expect(client.calls == 4)
    #expect(pool.inFlightCounts == [0])
  }

  @Test func avoidsBusySlotWhileStreamingBodyRemainsOpen() async throws {
    let gates = [StreamGate(), StreamGate()]
    let clients = gates.map { gate in
      StubHTTPClient { _, _ in
        let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
          Task {
            continuation.yield(ByteBuffer(string: "first-"))
            await gate.wait()
            continuation.yield(ByteBuffer(string: "second"))
            continuation.finish()
          }
        }
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: ["x-test": "yes"],
          body: .stream(stream)
        )
      }
    }
    let pool = P2CHTTPClient(clients: clients, seed: 42)

    let response1 = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/1"),
      timeout: .seconds(5)
    )
    var iterator1 = response1.body.makeAsyncIterator()
    let first1 = try await iterator1.next()
    #expect(first1.map { String(buffer: $0) } == "first-")
    #expect(pool.inFlightCounts.reduce(0, +) == 1)

    // With 1 of 2 slots active, any distinct random pair {0, 1} must select the idle slot.
    let response2 = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/2"),
      timeout: .seconds(5)
    )
    var iterator2 = response2.body.makeAsyncIterator()
    let first2 = try await iterator2.next()
    #expect(first2.map { String(buffer: $0) } == "first-")
    #expect(clients[0].calls == 1)
    #expect(clients[1].calls == 1)
    #expect(pool.inFlightCounts == [1, 1])

    await gates[0].release()
    await gates[1].release()

    let second1 = try await iterator1.next()
    #expect(second1.map { String(buffer: $0) } == "second")
    let eof1 = try await iterator1.next()
    #expect(eof1 == nil)
    // Eager release on EOF even while response1 remains in scope.
    #expect(response1.status == .ok)
    #expect(response1.headers.first(name: "x-test") == "yes")
    #expect(pool.inFlightCounts.reduce(0, +) == 1)

    let second2 = try await iterator2.next()
    #expect(second2.map { String(buffer: $0) } == "second")
    let eof2 = try await iterator2.next()
    #expect(eof2 == nil)
    _ = response2.version
    #expect(pool.inFlightCounts == [0, 0])
  }

  @Test func releasesLoadImmediatelyOnMidStreamError() async throws {
    let client = StubHTTPClient { _, _ in
      let stream = AsyncThrowingStream<ByteBuffer, any Error> { continuation in
        continuation.yield(ByteBuffer(string: "partial"))
        continuation.finish(throwing: P2CTestError())
      }
      return HTTPClientResponse(status: .ok, body: .stream(stream))
    }
    let pool = P2CHTTPClient(clients: [client], seed: 7)

    let response = try await pool.execute(
      request: HTTPClientRequest(url: "https://example.com/err"),
      timeout: .seconds(5)
    )
    #expect(pool.inFlightCounts == [1])
    var iterator = response.body.makeAsyncIterator()
    let chunk = try await iterator.next()
    #expect(chunk.map { String(buffer: $0) } == "partial")

    await #expect(throws: P2CTestError.self) {
      _ = try await iterator.next()
    }
    #expect(pool.inFlightCounts == [0])
  }

  @Test func releasesLoadOnEarlyDeinitWhenBodyIsUnread() async throws {
    let clients = (0..<2).map { _ in
      StubHTTPClient { _, _ in
        HTTPClientResponse(status: .created, body: .bytes(ByteBuffer(string: "unread")))
      }
    }
    let pool = P2CHTTPClient(clients: clients, seed: 99)

    @Sendable
    func fetchStatusOnly() async throws -> HTTPResponseStatus {
      let response = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com/unread"),
        timeout: .seconds(5)
      )
      return response.status
    }

    let status = try await fetchStatusOnly()
    #expect(status == .created)
    #expect(pool.inFlightCounts == [0, 0])
  }

  @Test func releasesLoadImmediatelyWhenExecuteThrowsBeforeHeaders() async {
    let clients = [
      StubHTTPClient { _, _ in throw P2CTestError() },
      StubHTTPClient { _, _ in throw P2CTestError() },
    ]
    let pool = P2CHTTPClient(clients: clients, seed: 123)

    await #expect(throws: P2CTestError.self) {
      _ = try await pool.execute(
        request: HTTPClientRequest(url: "https://example.com/fail"),
        timeout: .seconds(5)
      )
    }
    #expect(pool.inFlightCounts == [0, 0])
  }

  @Test func concurrentRequestsSpreadAcrossFourSlots() async throws {
    let barrierGate = StreamGate()
    let activeRequests = Atomic<Int>(0)
    let clients = (0..<4).map { _ in
      StubHTTPClient { _, _ in
        if activeRequests.add(1, ordering: .acquiringAndReleasing).newValue >= 8 {
          await barrierGate.release()
        }
        await barrierGate.wait()
        return HTTPClientResponse(status: .ok, body: .bytes(ByteBuffer(string: "done")))
      }
    }
    let pool = P2CHTTPClient(clients: clients, seed: 2026)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for idx in 0..<24 {
        group.addTask {
          let response = try await pool.execute(
            request: HTTPClientRequest(url: "https://example.com/\(idx)"),
            timeout: .seconds(5)
          )
          for try await _ in response.body {}
        }
      }
      try await group.waitForAll()
    }

    let counts = clients.map(\.calls)
    #expect(counts.reduce(0, +) == 24)
    #expect(counts.allSatisfy { $0 > 0 })
    #expect(pool.inFlightCounts == [0, 0, 0, 0])
  }
}
