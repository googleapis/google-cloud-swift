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

import struct AsyncHTTPClient.HTTPClientResponse
import struct NIOCore.ByteBuffer

/// An asynchronous sequence of response body chunks.
@_spi(GoogleCloudInternal) public struct _HTTPResponseBody: AsyncSequence, Sendable {
  public typealias Element = NIOCore.ByteBuffer

  let body: AsyncHTTPClient.HTTPClientResponse.Body

  public init(_ body: AsyncHTTPClient.HTTPClientResponse.Body) {
    self.body = body
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    var iterator: AsyncHTTPClient.HTTPClientResponse.Body.AsyncIterator

    public init(_ iterator: AsyncHTTPClient.HTTPClientResponse.Body.AsyncIterator) {
      self.iterator = iterator
    }

    public mutating func next() async throws -> NIOCore.ByteBuffer? {
      try await self.iterator.next()
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(self.body.makeAsyncIterator())
  }
}
