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
import struct Logging.Logger

/// A protocol to mock `AsyncHTTPClient.HTTPClient`.
///
/// The tests for `GoogleCloudGax.HttpClient`
@_spi(GoogleCloudInternal) public protocol _HTTPClientProtocol: Sendable {
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse
  func shutdown() async throws
}

extension _HTTPClientProtocol {
  public func shutdown() async throws {}
}
