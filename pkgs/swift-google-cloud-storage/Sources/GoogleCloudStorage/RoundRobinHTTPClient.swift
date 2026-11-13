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

import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
@_spi(GoogleCloudInternal) import GoogleGax
import Synchronization

/// Distributes HTTP requests across a fixed pool of `_HTTPClientProtocol` instances using
/// lock-free atomic round-robin selection.
final class RoundRobinHTTPClient: _HTTPClientProtocol, Sendable {
  private let clients: [any _HTTPClientProtocol]
  private let nextIndex = Atomic<UInt64>(0)

  init(clients: [any _HTTPClientProtocol]) {
    precondition(!clients.isEmpty, "RoundRobinHTTPClient requires at least one HTTP client")
    self.clients = clients
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    let index = Int(
      self.nextIndex.wrappingAdd(1, ordering: .relaxed).oldValue % UInt64(self.clients.count)
    )
    return try await self.clients[index].execute(request: request, timeout: timeout)
  }
}
