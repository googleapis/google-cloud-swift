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
import GoogleGax

/// The HTTP methods used by BigQuery.
enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
}

/// An HTTP request to BigQuery, independent of the HTTP client library.
struct HTTPRequest: Sendable {
  /// Where a request is sent.
  enum Target: Sendable, Equatable {
    /// A percent-encoded path relative to the endpoint, for example `/bigquery/v2/projects/p/jobs`.
    case path(String)
    /// An absolute URL, for example a resumable upload session.
    case url(String)
  }

  var method: HTTPMethod
  var target: Target
  var query: [URLQueryItem]
  var headers: [String: String]
  var body: Data?
  var options: RequestOptions

  /// Creates a request for a path relative to the endpoint.
  ///
  /// - Parameter path: a percent-encoded path. Use ``encode(segment:)`` for each variable segment.
  init(
    method: HTTPMethod,
    path: String,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    body: Data? = nil,
    options: RequestOptions = .init()
  ) {
    self.method = method
    self.target = .path(path)
    self.query = query
    self.headers = headers
    self.body = body
    self.options = options
  }

  /// Creates a request for an absolute URL.
  init(
    method: HTTPMethod,
    url: String,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    body: Data? = nil,
    options: RequestOptions = .init()
  ) {
    self.method = method
    self.target = .url(url)
    self.query = query
    self.headers = headers
    self.body = body
    self.options = options
  }

  /// Percent-encodes one path segment, such as a table ID containing `$` or `@`.
  static func encode(segment: String) -> String {
    segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
  }

  /// The unreserved characters of RFC 3986. Everything else is percent-encoded.
  private static let segmentAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

/// An HTTP response from BigQuery.
struct HTTPResponse: Sendable {
  var statusCode: Int

  /// The response headers, keyed by lowercased name.
  var headers: [String: String]

  var body: Data

  init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.statusCode = statusCode
    self.headers = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    self.body = body
  }

  /// The value of the header `name`, matched case-insensitively.
  func header(_ name: String) -> String? {
    self.headers[name.lowercased()]
  }
}

/// Sends HTTP requests. The production implementation uses `GoogleGax`; tests use a fake.
protocol HTTPTransport: Sendable {
  /// Sends `request` and returns the response, whatever its status code.
  ///
  /// - Parameter timeout: the maximum time for this attempt, or `nil` for the default.
  func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse
}
