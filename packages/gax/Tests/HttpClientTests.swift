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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing
@testable import GoogleCloudGax
import GoogleCloudAuth
import GoogleRpc

@Suite(.serialized) struct HttpClientTest {
  // Custom URLProtocol to mock responses
  class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
      return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      return request
    }

    override func startLoading() {
      guard let handler = MockURLProtocol.requestHandler else {
        fatalError("Handler not set.")
      }

      do {
        let (response, data) = try handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      } catch {
        client?.urlProtocol(self, didFailWithError: error)
      }
    }

    override func stopLoading() {}
  }

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
    let client = try HTTPClient(from: options, withDefaultEndpoint: endpoint)
    let query = [URLQueryItem(name: "$alt", value: "json")]
    let request = try await client.Request(path: inputPath, query: query)
    // Note the percent-escaped `?`
    #expect(
      request.url?.absoluteString == "http://localhost:1234/\(wantPath)?$alt=json")
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
      let client = try HTTPClient(from: options, withDefaultEndpoint: "https://localhost:1234")
      print("client=\(client)")
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
      let _ = try HTTPClient(from: options, withDefaultEndpoint: input)
    }
    guard case let .invalidEndpoint(msg) = error else {
      Issue.record("Mismatched error type, want .invalidEndpoint, got=\(error).")
      return
    }
    #expect(msg.contains(input), "error=\(error)")
  }

  @Test func postRequest() async throws {
    let endpoint = "http://localhost:8080"
    let path = "/v1/projects/my-project/secrets"
    let query = [URLQueryItem(name: "$alt", value: "json")]

    // Set up mock handler
    MockURLProtocol.requestHandler = { request in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path == path)
      #expect(request.url?.query == "$alt=json")

      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let responseData = Data("{}".utf8)
      return (response, responseData)
    }

    // Configure session with mock protocol
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let client = try HTTPClient(testSession: session, endpoint: endpoint)

    var request = try await client.Request(path: path, query: query)
    request.httpMethod = "POST"
    request.httpBody = "{}".data(using: .utf8)

    let (data, response) = try await client.data(for: request)

    #expect(response.statusCode == 200)
    #expect(!data.isEmpty)
  }

  @Test func getErrorDetails() async throws {
    let endpoint = "http://localhost:8080"
    let path = "/v1/projects/test-only-project/locations/us-central1/orchestrationClusters"
    let query = [URLQueryItem(name: "$alt", value: "json")]

    // Set up mock handler
    MockURLProtocol.requestHandler = { request in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == path)
      #expect(request.url?.query == "$alt=json")

      let response = HTTPURLResponse(
        url: request.url!, statusCode: 403, httpVersion: nil,
        headerFields: ["Content-Type": "application/json; charset=UTF-8"])!
      let responseData = Data(errorResponseWithDetails.utf8)
      return (response, responseData)
    }

    // Configure session with mock protocol
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let client = try HTTPClient(testSession: session, endpoint: endpoint)

    var request = try await client.Request(path: path, query: query)
    request.httpMethod = "GET"

    let response = await client.rpc(for: request)
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
    let query = [URLQueryItem(name: "$alt", value: "json")]

    // Set up mock handler
    MockURLProtocol.requestHandler = { request in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path == path)
      #expect(request.url?.query == "$alt=json")

      let response = HTTPURLResponse(
        url: request.url!, statusCode: 404, httpVersion: nil,
        headerFields: ["Content-Type": "text/html; charset=UTF-8"])!
      let responseData = "<!DOCTYPE html><html lang=en><title>Error 404</title></html>".data(
        using: .utf8)!
      return (response, responseData)
    }

    // Configure session with mock protocol
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let client = try HTTPClient(testSession: session, endpoint: endpoint)

    var request = try await client.Request(path: path, query: query)
    request.httpMethod = "GET"

    let response = await client.rpc(for: request)
    guard case let .failure(.http(httpError)) = response else {
      Issue.record("expected an http error response, got=\(response)")
      return
    }
    #expect(httpError.http_status_code == 404)
  }
}

let errorResponseWithDetails = """
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

let wantDetails: [StatusDetail] = [
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
