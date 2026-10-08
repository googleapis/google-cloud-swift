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
@_spi(GoogleCloudInternal) import GoogleGax
import NIOHTTP1

/// Sends requests with `GoogleGax._HTTPClient`, which adds authentication and standard headers.
struct GaxHTTPTransport: HTTPTransport {
  let client: GoogleGax._HTTPClient

  /// The attempt timeout when neither the request nor the client sets one.
  static let defaultTimeout: Duration = .seconds(60)

  func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
    var gaxRequest: GoogleGax._HTTPClientRequest
    switch request.target {
    case .path(let path):
      gaxRequest = try await self.client.newRequest(
        percentEncodedPath: path, query: request.query, options: request.options)
    case .url(let url):
      guard var components = URLComponents(string: url) else {
        throw RequestError.badURL(url)
      }
      if !request.query.isEmpty {
        components.queryItems = (components.queryItems ?? []) + request.query
      }
      gaxRequest = try await self.client.newRequest(
        urlComponents: components, options: request.options)
    }
    gaxRequest.setMethod(NIOHTTP1.HTTPMethod(rawValue: request.method.rawValue))
    for (name, value) in request.headers {
      gaxRequest.setHeader(name: name, value: value)
    }
    if let body = request.body {
      gaxRequest.setBody(data: body)
    }
    let response = try await gaxRequest.execute(timeout: timeout ?? Self.defaultTimeout)
    var headers: [String: String] = [:]
    for (name, value) in response.headers {
      headers[name.lowercased()] = value
    }
    let body = try await response.data()
    return HTTPResponse(statusCode: Int(response.status.code), headers: headers, body: body)
  }
}
