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
@_spi(GoogleCloudInternal) public import GoogleAuth
@_spi(GoogleCloudInternal) public import Logging

/// Implements a HTTP-only client for the Swift SDK client libraries.
@_spi(GoogleCloudInternal) public final class _HTTPClient: Sendable {
  let endpoint: _ResolvedEndpoint
  let credentials: any CredentialsProtocol
  let logger: Logger?
  let quotaProject: String?
  let inner: any _HTTPClientProtocol
  public let clientHeader: _ApiClientHeader

  // Creates a new client.
  public convenience init(
    from: ClientOptions,
    withDefaultEndpoint: String,
    clientHeader: _ApiClientHeader = .init()
  ) throws {
    try self.init(
      from: from,
      withDefaultEndpoint: withDefaultEndpoint,
      clientHeader: clientHeader,
      environment: ProcessInfo.processInfo.environment
    )
  }

  convenience init(
    from: ClientOptions,
    withDefaultEndpoint: String,
    clientHeader: _ApiClientHeader = .init(),
    environment: [String: String]
  ) throws {
    let resolvedEndpoint = try _ResolvedEndpoint(
      options: from,
      defaultEndpoint: withDefaultEndpoint,
      environment: environment
    )
    let credentials = try from.credentials ?? GoogleAuth.Credentials(environment: environment)
    self.init(
      from._httpClient ?? HTTPClientHolder(),
      endpoint: resolvedEndpoint,
      credentials: credentials,
      logger: from.logger,
      quotaProject: from.quotaProject,
      clientHeader: clientHeader
    )
  }

  @_spi(GoogleCloudInternal) public convenience init(
    _ inner: any _HTTPClientProtocol,
    endpoint: _ResolvedEndpoint,
    credentials: GoogleAuth.Credentials? = nil,
    logger: Logging.Logger? = nil,
    quotaProject: String? = nil,
    clientHeader: _ApiClientHeader = .init()
  ) throws {
    let resolvedCredentials = try credentials ?? GoogleAuth.Credentials(configuration: .anonymous)
    self.init(
      inner,
      endpoint: endpoint,
      credentials: resolvedCredentials as any CredentialsProtocol,
      logger: logger,
      quotaProject: quotaProject,
      clientHeader: clientHeader
    )
  }

  // Creates a new testing client.
  @_spi(GoogleCloudInternal) public convenience init(
    _ inner: any _HTTPClientProtocol, endpoint: String,
    credentials: GoogleAuth.Credentials? = nil,
    logger: Logging.Logger? = nil,
    quotaProject: String? = nil,
    defaultEndpoint: String? = nil,
    universeDomain: String = _UniverseDomain.defaultRawValue,
    clientHeader: _ApiClientHeader = .init()
  ) throws {
    let resolvedCredentials = try credentials ?? GoogleAuth.Credentials(configuration: .anonymous)
    try self.init(
      inner,
      endpoint: endpoint,
      credentials: resolvedCredentials as any CredentialsProtocol,
      logger: logger,
      quotaProject: quotaProject,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain,
      clientHeader: clientHeader
    )
  }

  convenience init(
    _ inner: any _HTTPClientProtocol, endpoint: String,
    credentials: any CredentialsProtocol,
    logger: Logging.Logger? = nil,
    quotaProject: String? = nil,
    defaultEndpoint: String? = nil,
    universeDomain: String = _UniverseDomain.defaultRawValue,
    clientHeader: _ApiClientHeader = .init()
  ) throws {
    if universeDomain.isEmpty {
      throw ClientError.invalidEndpoint("The universe_domain cannot be empty")
    }
    let resolvedEndpoint = try _ResolvedEndpoint(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint ?? endpoint,
      universeDomain: _UniverseDomain.resolve(universeDomain)
    )
    self.init(
      inner,
      endpoint: resolvedEndpoint,
      credentials: credentials,
      logger: logger,
      quotaProject: quotaProject,
      clientHeader: clientHeader
    )
  }

  init(
    _ inner: any _HTTPClientProtocol,
    endpoint: _ResolvedEndpoint,
    credentials: any CredentialsProtocol,
    logger: Logging.Logger? = nil,
    quotaProject: String? = nil,
    clientHeader: _ApiClientHeader = .init()
  ) {
    self.endpoint = endpoint
    self.credentials = credentials
    self.logger = logger
    self.quotaProject = quotaProject
    self.inner = inner
    var header = clientHeader
    header.setToken(.rest, version: gaxVersion())
    self.clientHeader = header
  }

  private func configureHeaders(
    on request: inout _HTTPClientRequest,
    options: RequestOptions,
    hostHeader: String? = nil
  ) async throws {
    let authHeaders: AuthHeaders
    do {
      try await self.credentials._validateUniverseDomain(self.endpoint.universeDomain)
      authHeaders = try await self.credentials.headers()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw RequestError.io(error)
    }
    let customHeaders = _sanitizeCustomHeaders(options.headers, excluding: authHeaders)
    for (key, value) in customHeaders {
      request.addHeader(name: key, value: value)
    }
    for (key, value) in authHeaders {
      request.addHeader(name: key, value: value)
    }
    if let effectiveQuotaProject = options.quotaProject ?? self.quotaProject {
      request.setHeader(name: _HeaderNames.userProject, value: effectiveQuotaProject)
    }
    request.setHeader(name: _HeaderNames.host, value: hostHeader ?? self.endpoint.hostHeader)
    request.setHeader(name: _HeaderNames.apiClient, value: self.clientHeader.build())
  }

  /// Validates that an absolute session `uri` is compatible with the client's configured endpoint
  /// and universe domain.
  ///
  /// - Throws: `RequestError.badURL(uri)` if `uri` fails scheme, port, host, or universe domain
  ///   validation.
  public func validateRequestURI(_ uri: String) throws {
    _ = try self.endpoint.resolveRequestURI(uri)
  }

  public func newRequest(
    path: String,
    query: [URLQueryItem],
    options: RequestOptions = .init()
  ) async throws -> _HTTPClientRequest {
    var components = self.endpoint.baseURL
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
    var components = self.endpoint.baseURL
    components.encodeQuery(query)
    components.percentEncodedPath = percentEncodedPath
    var request = _HTTPClientRequest(self.inner, url: components)
    try await self.configureHeaders(on: &request, options: options)
    return request
  }

  /// Creates a new authenticated request for an absolute session `uri`, validating its scheme,
  /// port, host, and universe domain before resolving credential headers.
  ///
  /// - Throws: `RequestError.badURL(uri)` if `uri` fails endpoint/universe validation,
  ///   `CancellationError` if the current task is cancelled while resolving credentials, or
  ///   `RequestError.io` wrapping credential or universe domain mismatch errors.
  public func newRequest(
    uri: String,
    options: RequestOptions = .init()
  ) async throws -> _HTTPClientRequest {
    let resolved = try self.endpoint.resolveRequestURI(uri)
    var request = _HTTPClientRequest(self.inner, url: resolved.components)
    try await self.configureHeaders(
      on: &request,
      options: options,
      hostHeader: resolved.hostHeader
    )
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
