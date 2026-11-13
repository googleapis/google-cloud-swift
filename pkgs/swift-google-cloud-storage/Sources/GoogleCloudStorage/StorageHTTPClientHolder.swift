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

import class AsyncHTTPClient.HTTPClient
import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
@_spi(GoogleCloudInternal) import GoogleGax
import struct NIOCore.TimeAmount

/// Owns a dedicated `AsyncHTTPClient.HTTPClient` instance (and its underlying connection pool) on
/// the shared `HTTPClient.defaultEventLoopGroup`, shutting it down asynchronously on `deinit`.
final class StorageHTTPClientHolder: _HTTPClientProtocol, Sendable {
  let inner = AsyncHTTPClient.HTTPClient()

  deinit {
    let copy = self.inner
    Task {
      do {
        try await copy.shutdown()
      } catch {
        // Ignore shutdown failures during deinitialization.
      }
    }
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    try await self.inner.execute(request, timeout: .init(timeout), logger: nil)
  }
}
