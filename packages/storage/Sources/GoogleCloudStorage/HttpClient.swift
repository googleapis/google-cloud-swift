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
// On Linux `URLSession` and friends are found in `FoundationNetworking`, ugh.
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudWkt
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax

/// Implements a HTTP-only client for the Swift SDK client libraries.
struct HTTPClient: Sendable {
  private static let sharedSession = URLSession(configuration: .ephemeral)

  let baseURL: URLComponents
  let credentials: GoogleCloudAuth.Credentials
  let inner: URLSession

  // Creates a new client.
  public init(from: ClientOptions, withDefaultEndpoint: String) throws {
    self.credentials = try from.credentials ?? GoogleCloudAuth.Credentials()
    let endpoint = from.endpoint ?? withDefaultEndpoint
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.inner = Self.sharedSession
  }

  // Creates a new testing client.
  @_spi(GoogleCloudInternal) public init(
    testSession: URLSession, endpoint: String, credentials: Credentials? = nil
  ) throws {
    self.baseURL = try Self.validateEndpoint(endpoint)
    self.credentials = try credentials ?? GoogleCloudAuth.Credentials(configuration: .anonymous)
    self.inner = testSession
  }

  static func validateEndpoint(_ endpoint: String) throws -> URLComponents {
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

  public func Request(path: String, query: [URLQueryItem]) async throws -> URLRequest {
    var components = self.baseURL
    components.path = path
    components.queryItems = query
    guard let url = components.url else {
      throw RequestError.binding("bad URL for path=\(path), baseURL=\(self.baseURL)")
    }
    var request = URLRequest(url: url)
    let headers = try await self.credentials.headers()
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return request
  }

  public func Request(percentEncodedPath: String, query: [URLQueryItem]) async throws -> URLRequest
  {
    var components = self.baseURL
    if !query.isEmpty {
      components.queryItems = query
    }
    components.percentEncodedPath = percentEncodedPath
    guard let url = components.url else {
      throw RequestError.binding("bad URL for path=\(percentEncodedPath), baseURL=\(self.baseURL)")
    }
    var request = URLRequest(url: url)
    let headers = try await self.credentials.headers()
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return request
  }

  func rpc(for request: URLRequest) async -> Result<(Data, HTTPURLResponse), RequestError> {
    do {
      let (data, response) = try await self.data(for: request)
      if !(200..<300).contains(response.statusCode) {
        return .failure(Self.parseError(data: data, response: response))
      }
      return .success((data, response))
    } catch let e as RequestError {
      return .failure(e)
    } catch let e {
      return .failure(.io(e))
    }
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await self.inner.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RequestError.badResponseType
    }
    return (data, httpResponse)
  }

  public static func parseError(data: Data, response: HTTPURLResponse) -> RequestError {
    if let s = response.value(forHTTPHeaderField: "Content-Type"), s.contains("application/json") {
      if let w = GoogleCloudGax._ErrorWrapper(data: data) {
        return RequestError.service(ServiceError(wrapper: w))
      }
    }
    return GoogleCloudGax.RequestError.http(
      GoogleCloudGax.HTTPDetails(
        http_status_code: response.statusCode,
        headers: [:],
        payload: data,
      ))
  }
}
