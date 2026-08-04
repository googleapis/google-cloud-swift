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
import Testing
import struct Logging.Logger
import struct DequeModule.Deque
import GoogleCloudAuth
import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
@_spi(GoogleCloudInternal) @testable import GoogleCloudGax

final class MockHTTPClient: HTTPClientProtocol, Sendable {
  typealias Handler =
    @Sendable (HTTPClientRequest, Duration) async throws -> HTTPClientResponse
  private let handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
  }

  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    try await handler(request, timeout)
  }
}
