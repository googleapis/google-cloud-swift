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

public import Foundation
import struct GoogleAuth.Credentials
import class AsyncHTTPClient.HTTPClient
import struct AsyncHTTPClient.HTTPClientRequest
import struct AsyncHTTPClient.HTTPClientResponse
@_spi(GoogleCloudInternal) public import Logging

/// Implements a HTTP-only client for the Swift SDK client libraries.
@_spi(GoogleCloudInternal) public struct _HTTPClient: Sendable {
  let baseURL: URLComponents
  let credentials: any _CredentialsProtocol
  let logger: Logger?
  let quotaProject: String?
  let inner: any _HTTPClientProtocol
  let hostHeader: String

  // Creates a new client.
  public init(from: ClientOptions, withDefaultEndpoint: String) throws {
    self.credentials = try from.credentials ?? GoogleAuth.Credentials()
    self.logger = from.logger
    self.quotaProject = from.quotaProject
    let endpoint = from.endpoint ?? withDefaultEndpoint
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.hostHeader = try _Host.header(
      endpoint: from.endpoint,
      defaultEndpoint: withDefaultEndpoint
    )
    self.inner = try HTTPClientHolder(rootCertificates: from.rootCertificates)
  }

  // Creates a new testing client.
  @_spi(GoogleCloudInternal) public init(
    _ inner: any _HTTPClientProtocol, endpoint: String,
    credentials: (any _CredentialsProtocol)? = nil,
    logger: Logging.Logger? = nil,
    quotaProject: String? = nil,
    defaultEndpoint: String? = nil
  ) throws {
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.credentials = try credentials ?? GoogleAuth.Credentials(configuration: .anonymous)
    self.logger = logger
    self.quotaProject = quotaProject
    self.inner = inner
    self.hostHeader = try _Host.header(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint ?? endpoint
    )
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

  private func configureHeaders(
    on request: inout _HTTPClientRequest,
    options: RequestOptions
  ) async throws {
    let authHeaders = try await self.credentials.headers()
    let customHeaders = _sanitizeCustomHeaders(options.headers, excluding: authHeaders)
    for (key, value) in customHeaders {
      request.setHeader(name: key, value: value)
    }
    for (key, value) in authHeaders {
      request.addHeader(name: key, value: value)
    }
    if let effectiveQuotaProject = options.quotaProject ?? self.quotaProject {
      request.setHeader(name: _HeaderNames.userProject, value: effectiveQuotaProject)
    }
    request.setHeader(name: _HeaderNames.host, value: self.hostHeader)
  }

  public func newRequest(
    path: String,
    query: [URLQueryItem],
    options: RequestOptions = .init()
  ) async throws -> _HTTPClientRequest {
    var components = self.baseURL
    components.path = path
    components.encodeQuery(query)
    var request = _HTTPClientRequest(self.inner, url: components)
    try await self.configureHeaders(on: &request, options: options)
    return request
  }

  public func newRequest(
    percentEncodedPath: String,
    query: [URLQueryItem],
    options: RequestOptions = .init()
  ) async throws
    -> _HTTPClientRequest
  {
    var components = self.baseURL
    components.encodeQuery(query)
    components.percentEncodedPath = percentEncodedPath
    var request = _HTTPClientRequest(self.inner, url: components)
    try await self.configureHeaders(on: &request, options: options)
    return request
  }

  public func newRequest(
    uri: String,
    options: RequestOptions = .init()
  ) async throws -> _HTTPClientRequest {
    guard var components = URLComponents(string: uri) else {
      throw RequestError.badURL(uri)
    }
    if let encoded = components.percentEncodedQuery {
      components.percentEncodedQuery = encoded.replacingOccurrences(of: ";", with: "%3B")
    }
    var request = _HTTPClientRequest(self.inner, url: components)
    try await self.configureHeaders(on: &request, options: options)
    return request
  }
}

private let queryItemAllowedCharacters: CharacterSet = {
  var set = CharacterSet.urlQueryAllowed
  set.remove(charactersIn: ";&=")
  return set
}()

extension URLComponents {
  fileprivate mutating func encodeQuery(_ query: [URLQueryItem]) {
    guard !query.isEmpty else { return }
    self.percentEncodedQueryItems = query.map { item in
      let name =
        item.name.addingPercentEncoding(withAllowedCharacters: queryItemAllowedCharacters)
        ?? item.name
      // `value` is optional, unlike `name`. We do not fall back to `item.value`
      // because passing unencoded characters to `percentEncodedQueryItems` causes a runtime fatal error.
      let value = item.value?.addingPercentEncoding(
        withAllowedCharacters: queryItemAllowedCharacters)
      return URLQueryItem(name: name, value: value)
    }
  }
}
