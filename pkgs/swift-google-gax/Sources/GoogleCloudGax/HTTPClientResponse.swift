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
@_spi(GoogleCloudInternal) import class GoogleCloudWKT._ProtoJSONDecoder
import struct AsyncHTTPClient.HTTPClientResponse
import struct NIOHTTP1.HTTPHeaders
import enum NIOHTTP1.HTTPResponseStatus
import struct NIOCore.ByteBuffer

/// Represents an HTTP response.
///
/// The generated code uses this type directly. It exposes the methods we
/// need, and nothing else.
@_spi(GoogleCloudInternal) public struct _HTTPClientResponse {
  // A default value for the maximum response size. Note that most gRPC client libraries limit
  // response sizes to 4 MiB, including successful value responses. Setting a limit that is 8 times
  // as large seems fine.
  static let defaultMaximumResponseSize = 32 * 1024 * 1024

  let response: AsyncHTTPClient.HTTPClientResponse

  public init(_ response: AsyncHTTPClient.HTTPClientResponse) {
    self.response = response
  }

  public var status: NIOHTTP1.HTTPResponseStatus {
    self.response.status
  }

  public var headers: NIOHTTP1.HTTPHeaders {
    self.response.headers
  }

  public var body: _HTTPResponseBody {
    _HTTPResponseBody(self.response.body)
  }

  public func data(upTo: Int) async throws -> Data {
    let buffer = try await self.response.body.collect(upTo: upTo)
    return Data(buffer: buffer)
  }

  public func data() async throws -> Data {
    try await data(upTo: Self.defaultMaximumResponseSize)
  }

  public consuming func drain() async {
    do {
      for try await _ in self.response.body {}
    } catch {}
  }

  public func isError() -> Bool {
    !(200...300).contains(self.response.status.code)
  }

  public consuming func decodeError() async -> RequestError {
    let data: Data
    do {
      let buffer = try await self.response.body.collect(upTo: Self.defaultMaximumResponseSize)
      data = Data(buffer: buffer)
    } catch let e {
      return .io(e)
    }
    let values = response.headers["Content-Type"]
    if values.contains(where: { $0.contains("application/json") }) {
      if let w = _ErrorWrapper(data: data) {
        return .service(ServiceError(wrapper: w))
      }
    }
    let headers = Dictionary(
      grouping: response.headers,
      by: { $0.name }
    )
    .mapValues { values in values.map { $0.value } }
    .mapValues { values in values.joined(separator: ";") }
    return .http(
      GoogleCloudGax.HTTPDetails(
        http_status_code: Int(response.status.code),
        headers: headers,
        payload: data,
      ))
  }

  public func decode<R>(_ type: R.Type) async throws -> Result<R, RequestError> where R: Decodable {
    let buffer: NIOCore.ByteBuffer
    do {
      buffer = try await self.response.body.collect(upTo: Self.defaultMaximumResponseSize)
    } catch let e {
      return .failure(.io(e))
    }
    // The `pointer` value is only valid for the duration of the closure.
    // SAFETY: The pointer does not escape the call to the closure, because decoding copies all the
    // data into new buffers.
    let payload = try buffer.withUnsafeReadableBytes({ (pointer: UnsafeRawBufferPointer) throws in
      let data = Data(pointer)
      let decoder = _ProtoJSONDecoder()
      return try decoder.decode(type, from: data)
    })
    return .success(payload)
  }
}
