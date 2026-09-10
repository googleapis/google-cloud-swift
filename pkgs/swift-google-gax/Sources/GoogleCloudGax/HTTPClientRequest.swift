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
import struct AsyncHTTPClient.HTTPClientRequest
import struct NIOCore.ByteBuffer
import struct NIOHTTP1.HTTPHeaders
import enum NIOHTTP1.HTTPMethod
import struct Logging.Logger
import NIOFoundationCompat

/// Represents the body of an HTTP request, encapsulating either `Foundation.Data`,
/// `NIOCore.ByteBuffer`, or a custom body without premature conversion or copying.
enum _RequestBody: Sendable {
  case data(Data)
  case byteBuffer(NIOCore.ByteBuffer)
  case custom(AsyncHTTPClient.HTTPClientRequest.Body)
}

/// Represents an HTTP request.
///
/// The generated code uses this type directly. It exposes the methods we
/// need, and nothing else.
@_spi(GoogleCloudInternal) public struct _HTTPClientRequest {
  let client: any _HTTPClientProtocol
  var components: URLComponents
  var headers: NIOHTTP1.HTTPHeaders
  var method: NIOHTTP1.HTTPMethod = .GET
  var body: _RequestBody? = nil

  // If the application and retry policy does not set a limit for each attempt we use this. The
  // expectation is that any RPC that takes this long or longer should be an LRO.
  static let defaultTimeout: Duration = .seconds(60)

  init(_ client: any _HTTPClientProtocol, url: URLComponents) {
    self.client = client
    self.components = url
    self.headers = NIOHTTP1.HTTPHeaders()
  }

  public mutating func setMethod(_ method: NIOHTTP1.HTTPMethod) {
    self.method = method
  }

  public mutating func addHeader(name: String, value: String) {
    self.headers.add(name: name, value: value)
  }

  public mutating func setHeader(name: String, value: String) {
    self.headers.replaceOrAdd(name: name, value: value)
  }

  public mutating func setBody(data: Data) {
    self.body = .data(data)
  }

  public mutating func setBody(data: Data, ofContentType: String) {
    self.body = .data(data)
    self.headers.replaceOrAdd(name: "Content-Type", value: ofContentType)
  }

  public mutating func setBody(buffer: NIOCore.ByteBuffer) {
    self.body = .byteBuffer(buffer)
  }

  public mutating func setBody(buffer: NIOCore.ByteBuffer, ofContentType: String) {
    self.body = .byteBuffer(buffer)
    self.headers.replaceOrAdd(name: "Content-Type", value: ofContentType)
  }

  public mutating func setBody<S>(
    stream: S,
    length: Int64? = nil
  ) where S: AsyncSequence & Sendable, S.Element == NIOCore.ByteBuffer {
    let bodyLength: AsyncHTTPClient.HTTPClientRequest.Body.Length =
      length.map { .known($0) } ?? .unknown
    self.body = .custom(.stream(stream, length: bodyLength))
  }

  public mutating func setBody<S>(
    stream: S,
    ofContentType: String,
    length: Int64? = nil
  ) where S: AsyncSequence & Sendable, S.Element == NIOCore.ByteBuffer {
    let bodyLength: AsyncHTTPClient.HTTPClientRequest.Body.Length =
      length.map { .known($0) } ?? .unknown
    self.body = .custom(.stream(stream, length: bodyLength))
    self.headers.replaceOrAdd(name: "Content-Type", value: ofContentType)
  }

  public mutating func setBody<S>(
    stream: S,
    length: Int64? = nil
  ) where S: AsyncSequence & Sendable, S.Element == Data {
    let bodyLength: AsyncHTTPClient.HTTPClientRequest.Body.Length =
      length.map { .known($0) } ?? .unknown
    self.body = .custom(.stream(stream.map { NIOCore.ByteBuffer(data: $0) }, length: bodyLength))
  }

  public mutating func setBody<S>(
    stream: S,
    ofContentType: String,
    length: Int64? = nil
  ) where S: AsyncSequence & Sendable, S.Element == Data {
    let bodyLength: AsyncHTTPClient.HTTPClientRequest.Body.Length =
      length.map { .known($0) } ?? .unknown
    self.body = .custom(.stream(stream.map { NIOCore.ByteBuffer(data: $0) }, length: bodyLength))
    self.headers.replaceOrAdd(name: "Content-Type", value: ofContentType)
  }

  public consuming func execute(timeout: Duration) async throws
    -> _HTTPClientResponse
  {
    guard let url = self.components.url else {
      throw RequestError.binding("bad URL for components=\(components)")
    }
    var request = AsyncHTTPClient.HTTPClientRequest(url: url.absoluteString)
    request.headers = self.headers
    request.method = self.method
    switch self.body {
    case .byteBuffer(let b):
      request.body = .bytes(b)
    case .data(let d):
      request.body = .bytes(.init(data: d))
    case .custom(let s):
      request.body = s
    case nil:
      break
    }
    let response = try await self.client.execute(request: request, timeout: timeout)
    return _HTTPClientResponse(response)
  }

  public consuming func execute() async throws -> _HTTPClientResponse {
    try await execute(timeout: Self.defaultTimeout)
  }

  public consuming func rpc<R>(_ type: R.Type, timeout: Duration? = nil) async
    -> Result<R, RequestError> where R: Decodable
  {
    do {
      let response = try await self.execute(timeout: timeout ?? Self.defaultTimeout)
      if response.isError() {
        return .failure(await response.decodeError())
      }
      return try await response.decode(type)
    } catch let e as RequestError {
      return .failure(e)
    } catch let e {
      return .failure(.io(e))
    }
  }
}
