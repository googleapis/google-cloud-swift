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
import struct NIOHTTP1.HTTPHeaders
import enum NIOHTTP1.HTTPMethod
import struct Logging.Logger

/// Represents an HTTP request.
///
/// The generated code uses this type directly. It exposes the methods we
/// need, and nothing else.
@_spi(GoogleCloudInternal) public struct _HTTPClientRequest {
  let client: any HTTPClientProtocol
  var components: URLComponents
  var headers: NIOHTTP1.HTTPHeaders
  var method: NIOHTTP1.HTTPMethod = .GET
  var body: Data? = nil

  // If the application and retry policy does not set a limit for each attempt we use this. The
  // expectation is that any RPC that takes this long or longer should be an LRO.
  static let defaultTimeout: Duration = .seconds(60)

  // Limit the maximum error response size. Note that most gRPC client libraries limit response
  // sizes to 4 MiB, including successful value responses. Setting a limit that is 8 times as large
  // seems fine.
  static let maximumErrorSize: Int = 32 * 1024 * 1024

  init(_ client: HTTPClientProtocol, url: URLComponents) {
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

  public mutating func setBody(data: Data, ofContentType: String) {
    self.body = data
    self.headers.add(name: "Content-Type", value: ofContentType)
  }

  consuming func execute(timeout: Duration) async throws
    -> _HTTPClientResponse
  {
    guard let url = self.components.url else {
      throw RequestError.binding("bad URL for components=\(components)")
    }
    var request = AsyncHTTPClient.HTTPClientRequest(url: url.absoluteString)
    request.headers = self.headers
    request.method = self.method
    if let b = self.body {
      request.body = .bytes(.init(data: b))
    }
    let response = try await self.client.execute(request: request, timeout: timeout)
    return _HTTPClientResponse(response)
  }

  public consuming func rpc(timeout: Duration? = nil) async
    -> Result<_HTTPClientResponse, RequestError>
  {
    do {
      let response = try await self.execute(timeout: timeout ?? Self.defaultTimeout)
      if !(200..<300).contains(response.status.code) {
        let data = try await response.data(upTo: Self.maximumErrorSize)
        return .failure(Self.parseError(data: data, response: response))
      }
      return .success(response)
    } catch let e as RequestError {
      return .failure(e)
    } catch let e {
      return .failure(.io(e))
    }
  }

  static func parseError(data: Data, response: _HTTPClientResponse) -> RequestError {
    let values = response.headers["Content-Type"]
    if values.contains(where: { $0.contains("application/json") }) {
      if let w = ErrorWrapper(data: data) {
        return RequestError.service(ServiceError(wrapper: w))
      }
    }
    let headers = Dictionary(
      grouping: response.headers,
      by: { $0.name }
    )
    .mapValues { values in values.map { $0.value } }
    .mapValues { values in values.joined(separator: ";") }
    return GoogleCloudGax.RequestError.http(
      GoogleCloudGax.HTTPDetails(
        http_status_code: Int(response.status.code),
        headers: headers,
        payload: data,
      ))
  }
}
