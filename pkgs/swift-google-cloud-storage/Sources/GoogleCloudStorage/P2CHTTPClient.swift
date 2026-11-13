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
import struct NIOCore.ByteBuffer
import Synchronization

/// Deterministic SplitMix64 PRNG for repeatable unit tests and fast uncontended P2C sampling
/// inside `Mutex<State>`.
struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    self.state &+= 0x9e3779b97f4a7c15
    var z = self.state
    z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
    z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
    return z ^ (z >> 31)
  }
}

/// Distributes HTTP requests across a fixed pool of `_HTTPClientProtocol` instances using
/// Power of Two Random Choices (`P2C`) over in-flight requests (including active response body
/// streams).
final class P2CHTTPClient: _HTTPClientProtocol, Sendable {
  private struct State: Sendable {
    var inFlightCounts: [Int]
    var rng: SplitMix64
  }

  private let clients: [any _HTTPClientProtocol]
  private let state: Mutex<State>

  convenience init(clients: [any _HTTPClientProtocol]) {
    self.init(clients: clients, seed: UInt64.random(in: UInt64.min...UInt64.max))
  }

  init(clients: [any _HTTPClientProtocol], seed: UInt64) {
    precondition(!clients.isEmpty, "P2CHTTPClient requires at least one HTTP client")
    self.clients = clients
    self.state = Mutex(
      State(
        inFlightCounts: Array(repeating: 0, count: clients.count),
        rng: SplitMix64(seed: seed)
      )
    )
  }

  var inFlightCounts: [Int] {
    self.state.withLock { $0.inFlightCounts }
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    let slotIndex = self.acquireSlot()
    let lease = LoadLease(pool: self, index: slotIndex)
    let response: HTTPClientResponse
    do {
      response = try await self.clients[slotIndex].execute(request: request, timeout: timeout)
    } catch {
      lease.release()
      throw error
    }
    return HTTPClientResponse(
      version: response.version,
      status: response.status,
      headers: response.headers,
      body: .stream(TrackedResponseBody(body: response.body, lease: lease)),
      history: response.history
    )
  }

  private func acquireSlot() -> Int {
    self.state.withLock { state in
      let count = state.inFlightCounts.count
      let selected: Int
      if count == 1 {
        selected = 0
      } else {
        let a = Int.random(in: 0..<count, using: &state.rng)
        let rawB = Int.random(in: 0..<(count - 1), using: &state.rng)
        let b = rawB >= a ? rawB + 1 : rawB
        selected = state.inFlightCounts[a] <= state.inFlightCounts[b] ? a : b
      }
      state.inFlightCounts[selected] += 1
      return selected
    }
  }

  private func releaseSlot(_ index: Int) {
    self.state.withLock { state in
      state.inFlightCounts[index] -= 1
    }
  }

  private final class LoadLease: Sendable {
    private let pool: P2CHTTPClient
    private let index: Int
    private let isReleased = Atomic<Bool>(false)

    init(pool: P2CHTTPClient, index: Int) {
      self.pool = pool
      self.index = index
    }

    func release() {
      let (exchanged, _) = self.isReleased.compareExchange(
        expected: false,
        desired: true,
        ordering: .acquiringAndReleasing
      )
      if exchanged {
        self.pool.releaseSlot(self.index)
      }
    }

    deinit {
      self.release()
    }
  }

  private struct TrackedResponseBody: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    let body: HTTPClientResponse.Body
    let lease: LoadLease

    struct AsyncIterator: AsyncIteratorProtocol {
      var iterator: HTTPClientResponse.Body.AsyncIterator
      let lease: LoadLease

      @concurrent
      mutating func next() async throws -> ByteBuffer? {
        do {
          let chunk = try await self.iterator.next()
          if chunk == nil {
            self.lease.release()
          }
          return chunk
        } catch {
          self.lease.release()
          throw error
        }
      }
    }

    func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(iterator: self.body.makeAsyncIterator(), lease: self.lease)
    }
  }
}
