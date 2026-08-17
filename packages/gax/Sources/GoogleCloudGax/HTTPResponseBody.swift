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

/// An asynchronous sequence of response body chunks.
@_spi(GoogleCloudInternal) public struct _HTTPResponseBody: AsyncSequence, Sendable {
  public typealias Element = Data

  let body: AsyncHTTPClient.HTTPClientResponse.Body

  public init(_ body: AsyncHTTPClient.HTTPClientResponse.Body) {
    self.body = body
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    var iterator: AsyncHTTPClient.HTTPClientResponse.Body.AsyncIterator

    public init(_ iterator: AsyncHTTPClient.HTTPClientResponse.Body.AsyncIterator) {
      self.iterator = iterator
    }

    public mutating func next() async throws -> Data? {
      guard let buffer = try await self.iterator.next() else { return nil }
      return Data(buffer: buffer)
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(self.body.makeAsyncIterator())
  }
}
