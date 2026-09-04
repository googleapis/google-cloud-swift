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
import struct GoogleCloudAuth.Credentials
import class AsyncHTTPClient.HTTPClient
import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
import struct Logging.Logger

/// Implements a HTTP-only client for the Swift SDK client libraries.
@_spi(GoogleCloudInternal) public struct _HTTPClient: Sendable {
  let baseURL: URLComponents
  let credentials: any _CredentialsProtocol
  let logger: Logger?
  let inner: any _HTTPClientProtocol

  // Creates a new client.
  public init(from: ClientOptions, withDefaultEndpoint: String) throws {
    self.credentials = try from.credentials ?? GoogleCloudAuth.Credentials()
    self.logger = from.logger
    let endpoint = from.endpoint ?? withDefaultEndpoint
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.inner = HTTPClientHolder()
  }

  // Creates a new testing client.
  @_spi(GoogleCloudInternal) public init(
    _ inner: any _HTTPClientProtocol, endpoint: String,
    credentials: (any _CredentialsProtocol)? = nil,
    logger: Logging.Logger? = nil,
  ) throws {
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.credentials = try credentials ?? GoogleCloudAuth.Credentials(configuration: .anonymous)
    self.logger = logger
    self.inner = inner
  }

  @_spi(GoogleCloudInternal) public static func validateEndpoint(_ endpoint: String) throws
    -> URLComponents
  {
    guard var parsed = URLComponents(string: endpoint) else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    parsed.queryItems = nil
    parsed.path = ""
    guard let scheme = parsed.scheme, (scheme == "http" || scheme == "https") else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    guard let host = parsed.host, !host.isEmpty else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    return parsed
  }

  public func newRequest(path: String, query: [URLQueryItem]) async throws -> _HTTPClientRequest {
    var components = self.baseURL
    components.path = path
    components.queryItems = query
    var request = _HTTPClientRequest(self.inner, url: components)
    let headers = try await self.credentials.headers()
    for (key, value) in headers {
      request.addHeader(name: key, value: value)
    }
    return request
  }

  public func newRequest(percentEncodedPath: String, query: [URLQueryItem]) async throws
    -> _HTTPClientRequest
  {
    var components = self.baseURL
    if !query.isEmpty {
      components.queryItems = query
    }
    components.percentEncodedPath = percentEncodedPath
    var request = _HTTPClientRequest(self.inner, url: components)
    let headers = try await self.credentials.headers()
    for (key, value) in headers {
      request.addHeader(name: key, value: value)
    }
    return request
  }

  public func newRequest(urlComponents: URLComponents) async throws -> _HTTPClientRequest {
    var request = _HTTPClientRequest(self.inner, url: urlComponents)
    let headers = try await self.credentials.headers()
    for (key, value) in headers {
      request.addHeader(name: key, value: value)
    }
    return request
  }

  public func newRequest(uri: String) async throws -> _HTTPClientRequest {
    guard let components = URLComponents(string: uri) else {
      throw RequestError.binding("bad URL for uri=\(uri)")
    }
    return try await newRequest(urlComponents: components)
  }

  public func shutdown() async throws {
    try await self.inner.shutdown()
  }
}
