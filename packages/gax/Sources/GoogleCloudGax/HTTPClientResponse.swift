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
import struct AsyncHTTPClient.HTTPClientResponse
import struct NIOHTTP1.HTTPHeaders
import enum NIOHTTP1.HTTPResponseStatus

/// Represents an HTTP response.
///
/// The generated code uses this type directly. It exposes the methods we
/// need, and nothing else.
@_spi(GoogleCloudInternal) public struct _HTTPClientResponse {
  let response: AsyncHTTPClient.HTTPClientResponse

  init(_ response: AsyncHTTPClient.HTTPClientResponse) {
    self.response = response
  }

  public var status: NIOHTTP1.HTTPResponseStatus {
    self.response.status
  }

  public var headers: NIOHTTP1.HTTPHeaders {
    self.response.headers
  }

  public func data(upTo: Int) async throws -> Data {
    let buffer = try await self.response.body.collect(upTo: upTo)
    return Data(buffer: buffer)
  }
}
