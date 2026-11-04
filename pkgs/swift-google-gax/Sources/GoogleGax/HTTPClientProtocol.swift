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

@_spi(GoogleCloudInternal) public import AsyncHTTPClient
import struct NIOCore.TimeAmount

/// A protocol to mock `AsyncHTTPClient.HTTPClient`.
///
/// Allow testing `GoogleGax._HTTPClient` with a mock HTTP client.
@_spi(GoogleCloudInternal) public protocol _HTTPClientProtocol: Sendable {
  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse
}

/// Adapts a shared `AsyncHTTPClient.HTTPClient` to `_HTTPClientProtocol`.
struct SharedHTTPClient: _HTTPClientProtocol {
  /// Process-wide shared `HTTPClient` using default configuration (`decompression: .disabled`).
  ///
  /// Unlike `HTTPClient.shared` (`.singletonConfiguration`), keeping automatic decompression
  /// disabled avoids injecting `Accept-Encoding: deflate, gzip` on outbound requests and prevents
  /// `NIOHTTPResponseDecompressor` from decompressing `Content-Encoding: gzip` streams behind
  /// callers that verify wire checksums or preserve compressed bytes (such as `GoogleCloudStorage`).
  static let defaultClient = AsyncHTTPClient.HTTPClient()

  let inner: AsyncHTTPClient.HTTPClient

  init(_ inner: AsyncHTTPClient.HTTPClient = SharedHTTPClient.defaultClient) {
    self.inner = inner
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    try await self.inner.execute(request, timeout: .init(timeout), logger: nil)
  }
}
