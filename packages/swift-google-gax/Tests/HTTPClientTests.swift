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
import Testing
import struct Logging.Logger
@_spi(GoogleCloudInternal) @testable import GoogleCloudGax
import GoogleCloudAuth
import GoogleRpc
import struct GoogleCloudWKT.Empty
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

@Suite struct HTTPClientTests {
  @Test(arguments: [
    // A `?` in the path results in a percent-encoded `?` == %3F
    ("/path?$name=value", "path%3F$name=value"),
    // A percent-encoded `?` in the path results in a percent-encoded `%` == %25
    ("/path%3F$name=value", "path%253F$name=value"),
  ]) func escapePath(
    inputPath: String, wantPath: String
  ) async throws {
    let endpoint = "http://localhost:1234"
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with { $0.credentials = credentials }
    let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
    let query = [URLQueryItem(name: "$alt", value: "json")]
    let request = try await client.newRequest(path: inputPath, query: query)
    // Note the percent-escaped `?`
    #expect(
      request.components.url?.absoluteString == "http://localhost:1234/\(wantPath)?$alt=json")
  }

  @Test(arguments: [
    // Pre-encoded characters like %2F, %20, %3F are preserved without re-encoding
    (
      "/path/to/folder%2Ffile.json",
      "http://localhost:1234/path/to/folder%2Ffile.json?$alt=json"
    ),
    (
      "/path%20with%20spaces/item",
      "http://localhost:1234/path%20with%20spaces/item?$alt=json"
    ),
    (
      "/path%3Fname=value",
      "http://localhost:1234/path%3Fname=value?$alt=json"
    ),
  ]) func percentEncodedPath(
    inputPath: String, wantURL: String
  ) async throws {
    let endpoint = "http://localhost:1234"
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with { $0.credentials = credentials }
    let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
    let query = [URLQueryItem(name: "$alt", value: "json")]
    let request = try await client.newRequest(percentEncodedPath: inputPath, query: query)
    #expect(request.components.url?.absoluteString == wantURL)
  }

  @Test func requestFromURI() async throws {
    let endpoint = "http://localhost:1234"
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with { $0.credentials = credentials }
    let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
    let uri = "https://storage.googleapis.com/upload/storage/v1/b/my-bucket/o?upload_id=12345"
    var request = try await client.newRequest(uri: uri)
    request.setHeader(name: "X-Test-Header", value: "TestValue")
    request.setBody(data: Data("test".utf8))
    #expect(request.components.url?.absoluteString == uri)
    #expect(request.headers["X-Test-Header"] == ["TestValue"])
    guard case .data(let data) = request.body else {
      Issue.record("expected .data body")
      return
    }
    #expect(data == Data("test".utf8))

    var buffer = ByteBufferAllocator().buffer(capacity: 4)
    buffer.writeString("test2")
    request.setBody(buffer: buffer)
    guard case .byteBuffer(let buf) = request.body else {
      Issue.record("expected .byteBuffer body")
      return
    }
    #expect(buf == buffer)
  }

  @Test(arguments: [
    "bad-bad-bad",
    "htt://localhost:1",
    "file:///etc/passwd",
    "http:///",
    "https:///",
  ]) func badEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = input
    }
    let error = #expect(throws: ClientError.self) {
      let _ = try _HTTPClient(from: options, withDefaultEndpoint: "https://localhost:1234")
    }
    guard case let .invalidEndpoint(msg) = error else {
      Issue.record("Mismatched error type, want .invalidEndpoint, got=\(error).")
      return
    }
    #expect(msg.contains(input), "error=\(error)")
  }

  @Test(arguments: [
    "bad-bad-bad",
    "htt://localhost:1",
    "file:///etc/passwd",
    "http:///",
    "https:///",
  ]) func badDefaultEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    let error = #expect(throws: ClientError.self) {
      let _ = try _HTTPClient(from: options, withDefaultEndpoint: input)
    }
    guard case let .invalidEndpoint(msg) = error else {
      Issue.record("Mismatched error type, want .invalidEndpoint, got=\(error).")
      return
    }
    #expect(msg.contains(input), "error=\(error)")
  }

  @Test func postRequest() async throws {
    let mock = MockHTTPClient { (request, timeout) in
      #expect(timeout == .seconds(1))
      #expect(request.method == .POST)
      #expect(request.url == "http://localhost:8080/v1/projects/my-project/secrets?$alt=json")

      return HTTPClientResponse(
        version: .http1_1,
        status: .ok,
        body: .bytes(.init(string: "{}"))
      )
    }

    let endpoint = "http://localhost:8080"
    let path = "/v1/projects/my-project/secrets"
    let client = try _HTTPClient(mock, endpoint: endpoint)
    var request = try await client.newRequest(
      path: path,
      query: [URLQueryItem(name: "$alt", value: "json")],
    )
    request.setMethod(.POST)
    request.setBody(data: .init("{}".utf8), ofContentType: "application/json")
    let response = try await request.execute(timeout: .seconds(1))
    #expect(response.status == .ok)
    let data = try await response.data(upTo: 1024)
    #expect(data == .init("{}".utf8))
  }

  @Test func rpcNoTimeout() async throws {
    let mock = MockHTTPClient { (request, timeout) in
      #expect(timeout == _HTTPClientRequest.defaultTimeout)
      #expect(request.method == .GET)
      #expect(request.url == "http://localhost:8080/v1/projects/my-project/secrets?$alt=json")

      return HTTPClientResponse(
        version: .http1_1,
        status: .ok,
        body: .bytes(.init(string: #"{"name":"test-name", "value":"test-value"}"#))
      )
    }

    let endpoint = "http://localhost:8080"
    let path = "/v1/projects/my-project/secrets"
    let client = try _HTTPClient(mock, endpoint: endpoint)
    var request = try await client.newRequest(
      path: path,
      query: [URLQueryItem(name: "$alt", value: "json")],
    )
    request.setMethod(.GET)
    guard case .success(let response) = await request.rpc(ResponseType.self) else {
      Issue.record("expected a successful RPC")
      return
    }
    #expect(response == ResponseType(name: "test-name", value: "test-value"))
  }

  @Test func getErrorDetails() async throws {
    let endpoint = "http://localhost:8080"
    let path = "/v1/projects/test-only-project/locations/us-central1/orchestrationClusters"
    let url = "\(endpoint)\(path)?$alt=json"

    let mock = MockHTTPClient { (request, timeout) in
      #expect(request.method == .GET)
      #expect(request.url == url)

      return HTTPClientResponse(
        version: .http1_1,
        status: .forbidden,
        headers: .init([("Content-Type", "application/json; charset=UTF-8")]),
        body: .bytes(.init(string: errorResponseWithDetails))
      )
    }

    let client = try _HTTPClient(mock, endpoint: endpoint)
    let request = try await client.newRequest(
      path: path, query: [URLQueryItem(name: "$alt", value: "json")])
    let response = await request.rpc(ResponseType.self, timeout: .seconds(1))
    guard case let .failure(.service(serviceError)) = response else {
      Issue.record("expected an service error response, got=\(response)")
      return
    }
    #expect(serviceError.code == Code.permissionDenied, "\(serviceError)")
    #expect(serviceError.message.starts(with: "Telco Automation API"), "\(serviceError)")
    #expect(serviceError.details == wantDetails, "\(serviceError)")
  }

  @Test func getHttpError() async throws {
    let endpoint = "http://localhost:8080"
    let path = "/v1/projects//locations/us-central1/orchestrationClusters"
    let url = "\(endpoint)\(path)?$alt=json"

    let mock = MockHTTPClient { (request, _) in
      #expect(request.method == .GET)
      #expect(request.url == url)

      return HTTPClientResponse(
        version: .http1_1,
        status: .notFound,
        headers: .init([("Content-Type", "text/html; charset=UTF-8")]),
        body: .bytes(.init(string: "<!DOCTYPE html><html lang=en><title>Error 404</title></html>"))
      )
    }

    let client = try _HTTPClient(mock, endpoint: endpoint)
    let request = try await client.newRequest(
      path: path, query: [URLQueryItem(name: "$alt", value: "json")])

    let response = await request.rpc(ResponseType.self)
    guard case let .failure(.http(httpError)) = response else {
      Issue.record("expected an http error response, got=\(response)")
      return
    }
    #expect(httpError.http_status_code == 404)
  }

  @Test("verify the client when used as GAPICs do for Create-like operations")
  func useAsGAPICCreate() async throws {
    let clientHeader = GoogleCloudGax._gapicApiClientHeader(packageVersion: "1.2.3")
    var wantURL = URLComponents()
    wantURL.scheme = "https"
    wantURL.host = "test-only.googleapis.com"
    wantURL.path = "/v1/projects/p/things"
    wantURL.queryItems = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int"),
      URLQueryItem(name: "thingId", value: "test-only-thing-id"),
    ]
    let wantURLString = wantURL.url?.absoluteString
    let requestBody = Data(#"{"thingAttribute":"test-value"}"#.utf8)
    let responseBody = #"{"name":"projects/p/things/test-only-thing-id"}"#

    let mockCredentials = MockCredentials([
      {
        return [
          ("authorization", "test-only-auth"),
          ("x-goog-auth", "test-only-auth2"),
        ]
      }
    ])
    let mock = MockHTTPClient { @Sendable (request, _) in
      #expect(request.method == .POST)
      #expect(request.url == wantURLString)
      #expect(request.headers[_HeaderNames.apiClient] == [clientHeader])
      #expect(request.headers["authorization"] == ["test-only-auth"])
      #expect(request.headers["x-goog-auth"] == ["test-only-auth2"])
      #expect(request.headers["content-type"] == ["application/json"])

      let buffer = try await request.body!.collect(upTo: 1024)
      #expect(Data(buffer: buffer) == requestBody)

      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json; charset=UTF-8")]),
        body: .bytes(.init(string: responseBody))
      )
    }

    let client = try _HTTPClient(
      mock, endpoint: "https://test-only.googleapis.com", credentials: mockCredentials)

    let path = "/v1/projects/p/things"
    var query = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    let encoder = GoogleCloudGax._QueryParameterEncoder()
    query.append(contentsOf: try encoder.encode("test-only-thing-id", prefix: "thingId"))
    var req = try await client.newRequest(path: path, query: query)
    req.setMethod(.POST)
    req.addHeader(name: _HeaderNames.apiClient, value: clientHeader)
    req.setBody(data: requestBody, ofContentType: "application/json")
    let response = try await req.rpc(ResponseType.self).get()
    #expect(response == ResponseType(name: "projects/p/things/test-only-thing-id", value: ""))
  }

  @Test("verify the client when used as GAPICs do for Get-like operations")
  func useAsGAPICGet() async throws {
    let clientHeader = GoogleCloudGax._gapicApiClientHeader(packageVersion: "1.2.3")
    var wantURL = URLComponents()
    wantURL.scheme = "https"
    wantURL.host = "test-only.googleapis.com"
    wantURL.path = "/v1/projects/p/things/test-only-thing-id"
    wantURL.queryItems = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    let wantURLString = wantURL.url?.absoluteString
    let responseBody = #"{"name":"projects/p/things/test-only-thing-id","value":"test-value"}"#

    let mockCredentials = MockCredentials([
      {
        return [
          ("authorization", "test-only-auth"),
          ("x-goog-auth", "test-only-auth2"),
        ]
      }
    ])
    let mock = MockHTTPClient { @Sendable (request, _) in
      #expect(request.method == .GET)
      #expect(request.url == wantURLString)
      #expect(request.headers[_HeaderNames.apiClient] == [clientHeader])
      #expect(request.headers["authorization"] == ["test-only-auth"])
      #expect(request.headers["x-goog-auth"] == ["test-only-auth2"])
      #expect(request.headers["content-type"] == [])
      #expect(request.body == nil)

      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json; charset=UTF-8")]),
        body: .bytes(.init(string: responseBody))
      )
    }

    let client = try _HTTPClient(
      mock, endpoint: "https://test-only.googleapis.com", credentials: mockCredentials)

    let path = "/v1/projects/p/things/test-only-thing-id"
    let query = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    var req = try await client.newRequest(path: path, query: query)
    req.setMethod(.GET)
    req.addHeader(name: _HeaderNames.apiClient, value: clientHeader)
    let response = try await req.rpc(ResponseType.self).get()
    #expect(
      response == ResponseType(name: "projects/p/things/test-only-thing-id", value: "test-value"))
  }

  @Test("verify the client when used as GAPICs do for Delete-like operations")
  func useAsGAPICDelete() async throws {
    let clientHeader = GoogleCloudGax._gapicApiClientHeader(packageVersion: "1.2.3")
    var wantURL = URLComponents()
    wantURL.scheme = "https"
    wantURL.host = "test-only.googleapis.com"
    wantURL.path = "/v1/projects/p/things/test-only-thing-id"
    wantURL.queryItems = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    let wantURLString = wantURL.url?.absoluteString

    let mockCredentials = MockCredentials([
      {
        return [
          ("authorization", "test-only-auth"),
          ("x-goog-auth", "test-only-auth2"),
        ]
      }
    ])
    let mock = MockHTTPClient { @Sendable (request, _) in
      #expect(request.method == .GET)
      #expect(request.url == wantURLString)
      #expect(request.headers[_HeaderNames.apiClient] == [clientHeader])
      #expect(request.headers["authorization"] == ["test-only-auth"])
      #expect(request.headers["x-goog-auth"] == ["test-only-auth2"])
      #expect(request.headers["content-type"] == [])
      #expect(request.body == nil)

      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json; charset=UTF-8")]),
        body: .bytes(.init(string: "{}")),
      )
    }

    let client = try _HTTPClient(
      mock, endpoint: "https://test-only.googleapis.com", credentials: mockCredentials)

    let path = "/v1/projects/p/things/test-only-thing-id"
    let query = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    var req = try await client.newRequest(path: path, query: query)
    req.setMethod(.GET)
    req.addHeader(name: _HeaderNames.apiClient, value: clientHeader)
    _ = try await req.rpc(GoogleCloudWKT.Empty.self).get()
  }

  @Test("verify the client when used as GAPICs do for Delete-like operations")
  func useAsGAPICDeleteWithError() async throws {
    let clientHeader = GoogleCloudGax._gapicApiClientHeader(packageVersion: "1.2.3")
    var wantURL = URLComponents()
    wantURL.scheme = "https"
    wantURL.host = "test-only.googleapis.com"
    wantURL.path = "/v1/projects/p/things/test-only-thing-id"
    wantURL.queryItems = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    let wantURLString = wantURL.url?.absoluteString

    let mockCredentials = MockCredentials([
      {
        return [
          ("authorization", "test-only-auth"),
          ("x-goog-auth", "test-only-auth2"),
        ]
      }
    ])
    let mock = MockHTTPClient { @Sendable (request, _) in
      #expect(request.method == .GET)
      #expect(request.url == wantURLString)
      #expect(request.headers[_HeaderNames.apiClient] == [clientHeader])
      #expect(request.headers["authorization"] == ["test-only-auth"])
      #expect(request.headers["x-goog-auth"] == ["test-only-auth2"])
      #expect(request.headers["content-type"] == [])
      #expect(request.body == nil)

      return HTTPClientResponse(
        version: .http2,
        status: .forbidden,
        headers: .init([("Content-Type", "application/json; charset=UTF-8")]),
        body: .bytes(.init(string: errorResponseWithDetails))
      )
    }

    let client = try _HTTPClient(
      mock, endpoint: "https://test-only.googleapis.com", credentials: mockCredentials)

    let path = "/v1/projects/p/things/test-only-thing-id"
    let query = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    var req = try await client.newRequest(path: path, query: query)
    req.setMethod(.GET)
    req.addHeader(name: _HeaderNames.apiClient, value: clientHeader)
    let e = await #expect(throws: GoogleCloudGax.RequestError.self) {
      _ = try (await req.rpc(GoogleCloudWKT.Empty.self)).get()
    }
    guard case .service(let serviceError) = e else {
      Issue.record("expected service error , got \(e)")
      return
    }
    #expect(serviceError.code == Code.permissionDenied, "\(serviceError)")
    #expect(serviceError.message.starts(with: "Telco Automation API"), "\(serviceError)")
    #expect(serviceError.details == wantDetails, "\(serviceError)")
  }

  @Test("verify the client when used as GAPICs do for Delete-like operations")
  func useAsGAPICDeleteWithTransportError() async throws {
    let clientHeader = GoogleCloudGax._gapicApiClientHeader(packageVersion: "1.2.3")
    var wantURL = URLComponents()
    wantURL.scheme = "https"
    wantURL.host = "test-only.googleapis.com"
    wantURL.path = "/invalid/path"
    wantURL.queryItems = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    let wantURLString = wantURL.url?.absoluteString
    let responsePayload = "<!DOCTYPE html><html lang=en><title>Error 404</title></html>"

    let mockCredentials = MockCredentials([
      {
        return [
          ("authorization", "test-only-auth"),
          ("x-goog-auth", "test-only-auth2"),
        ]
      }
    ])
    let mock = MockHTTPClient { @Sendable (request, _) in
      #expect(request.method == .GET)
      #expect(request.url == wantURLString)
      #expect(request.headers[_HeaderNames.apiClient] == [clientHeader])
      #expect(request.headers["authorization"] == ["test-only-auth"])
      #expect(request.headers["x-goog-auth"] == ["test-only-auth2"])
      #expect(request.headers["content-type"] == [])
      #expect(request.body == nil)

      return HTTPClientResponse(
        version: .http2,
        status: .forbidden,
        headers: .init([
          ("Content-Type", "text/html; charset=UTF-8"),
          ("x-goog-test-only", "test-header"),
        ]),
        body: .bytes(.init(string: responsePayload))
      )
    }

    let client = try _HTTPClient(
      mock, endpoint: "https://test-only.googleapis.com", credentials: mockCredentials)

    let path = "/invalid/path"
    let query = [
      URLQueryItem(name: "$alt", value: "json;enum-encoding=int")
    ]
    var req = try await client.newRequest(path: path, query: query)
    req.setMethod(.GET)
    req.addHeader(name: _HeaderNames.apiClient, value: clientHeader)
    let e = await #expect(throws: GoogleCloudGax.RequestError.self) {
      _ = try (await req.rpc(GoogleCloudWKT.Empty.self)).get()
    }
    guard case .http(let httpError) = e else {
      Issue.record("expected service error , got \(e)")
      return
    }
    #expect(httpError.http_status_code == HTTPResponseStatus.forbidden.code)
    #expect(httpError.payload == Data(responsePayload.utf8))
    #expect(httpError.headers["x-goog-test-only"] == "test-header")
  }

  @Test func streamingBodyByteBuffer() async throws {
    let chunks = ["Hello, ", "world", "!"].map { str -> NIOCore.ByteBuffer in
      var buf = ByteBufferAllocator().buffer(capacity: str.utf8.count)
      buf.writeString(str)
      return buf
    }

    let stream = AsyncStream<NIOCore.ByteBuffer> { continuation in
      for chunk in chunks {
        continuation.yield(chunk)
      }
      continuation.finish()
    }

    let mock = MockHTTPClient { (request, timeout) in
      #expect(request.method == .POST)
      #expect(request.url == "http://localhost:8080/upload")
      let body = try #require(request.body)
      let collected = try await body.collect(upTo: 1024)
      #expect(String(buffer: collected) == "Hello, world!")

      return HTTPClientResponse(
        version: .http1_1,
        status: .ok,
        body: .bytes(.init(string: "{}"))
      )
    }

    let client = try _HTTPClient(mock, endpoint: "http://localhost:8080")
    var request = try await client.newRequest(uri: "http://localhost:8080/upload")
    request.setMethod(.POST)
    request.setBody(stream: stream, ofContentType: "application/octet-stream", length: 13)

    let response = try await request.execute()
    #expect(response.status == .ok)
  }

  @Test func streamingBodyData() async throws {
    let chunks = ["Chunk1", "Chunk2"].map { Data($0.utf8) }

    let stream = AsyncStream<Data> { continuation in
      for chunk in chunks {
        continuation.yield(chunk)
      }
      continuation.finish()
    }

    let mock = MockHTTPClient { (request, timeout) in
      #expect(request.method == .PUT)
      #expect(request.url == "http://localhost:8080/upload")
      let body = try #require(request.body)
      let collected = try await body.collect(upTo: 1024)
      #expect(String(buffer: collected) == "Chunk1Chunk2")

      return HTTPClientResponse(
        version: .http1_1,
        status: .ok,
        body: .bytes(.init(string: "{}"))
      )
    }

    let client = try _HTTPClient(mock, endpoint: "http://localhost:8080")
    var request = try await client.newRequest(uri: "http://localhost:8080/upload")
    request.setMethod(.PUT)
    request.setBody(stream: stream)

    let response = try await request.execute()
    #expect(response.status == .ok)
  }

  @Test func shutdownIsIdempotent() async throws {
    let endpoint = "http://localhost:1234"
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with { $0.credentials = credentials }
    let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
    try await client.shutdown()
    // Second shutdown must be a safe idempotent no-op
    try await client.shutdown()
  }

  /// A test response type.
  struct ResponseType: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
  }
}

fileprivate let errorResponseWithDetails = """
  {
    "error": {
      "code": 403,
      "message": "Telco Automation API has not been used in project test-only-project before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project then retry. If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry.",
      "status": "PERMISSION_DENIED",
      "details": [
        {
          "@type": "type.googleapis.com/google.rpc.ErrorInfo",
          "reason": "SERVICE_DISABLED",
          "domain": "googleapis.com",
          "metadata": {
            "activationUrl": "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project",
            "service": "telcoautomation.googleapis.com",
            "consumer": "projects/test-only-project",
            "containerInfo": "test-only-project",
            "serviceTitle": "Telco Automation API"
          }
        },
        {
          "@type": "type.googleapis.com/google.rpc.LocalizedMessage",
          "locale": "en-US",
          "message": "Telco Automation API has not been used in project test-only-project before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project then retry. If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry."
        },
        {
          "@type": "type.googleapis.com/google.rpc.Help",
          "links": [
            {
              "description": "Google developers console API activation",
              "url": "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project"
            }
          ]
        }
      ]
    }
  }
  """

fileprivate let wantDetails: [StatusDetail] = [
  .errorInfo(
    ErrorInfo().with {
      $0.reason = "SERVICE_DISABLED"
      $0.domain = "googleapis.com"
      $0.metadata = [
        "activationUrl":
          "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project",
        "service": "telcoautomation.googleapis.com",
        "consumer": "projects/test-only-project",
        "containerInfo": "test-only-project",
        "serviceTitle": "Telco Automation API",
      ]
    }),
  .localizedMessage(
    LocalizedMessage().with {
      $0.locale = "en-US"
      $0.message =
        "Telco Automation API has not been used in project test-only-project before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project then retry. If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry."
    }),
  .help(
    Help().with {
      $0.links = [
        Help.Link().with {
          $0.description = "Google developers console API activation"
          $0.url =
            "https://console.developers.google.com/apis/api/telcoautomation.googleapis.com/overview?project=test-only-project"
        }
      ]
    }),
]
