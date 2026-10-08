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
import Synchronization

@testable import GoogleCloudBigQuery

/// An `HTTPTransport` that records requests and replays scripted responses.
///
/// ```swift
/// let fake = FakeHTTPTransport()
/// fake.enqueue(json: #"{"datasetReference": {"projectId": "p", "datasetId": "d"}}"#)
/// let client = fake.client()
/// _ = try await client.getDataset(DatasetID(datasetID: "d"))
/// #expect(fake.requests.first?.method == .get)
/// ```
final class FakeHTTPTransport: HTTPTransport {
  /// A scripted reply: a response, or an error thrown by the transport.
  enum Reply: Sendable {
    case response(HTTPResponse)
    case error(any Error)
  }

  private struct State {
    var replies: [Reply] = []
    var requests: [HTTPRequest] = []
    var timeouts: [Duration?] = []
  }

  private let state = Mutex(State())

  init() {}

  /// Queues a reply. Replies are consumed in order; an exhausted queue fails the request.
  func enqueue(_ reply: Reply) {
    self.state.withLock { $0.replies.append(reply) }
  }

  /// Queues a JSON response.
  func enqueue(status: Int = 200, json: String = "{}", headers: [String: String] = [:]) {
    self.enqueue(
      .response(HTTPResponse(statusCode: status, headers: headers, body: Data(json.utf8))))
  }

  /// Queues a BigQuery error response with the given status and reasons.
  func enqueueError(status: Int, reasons: [String] = [], message: String = "error") {
    let errors = reasons.map { #"{"reason": "\#($0)", "message": "\#(message)"}"# }
    self.enqueue(
      status: status,
      json:
        #"{"error": {"code": \#(status), "message": "\#(message)", "errors": [\#(errors.joined(separator: ","))]}}"#
    )
  }

  /// The requests sent so far, in order. Includes the common query parameters.
  var requests: [HTTPRequest] { self.state.withLock { $0.requests } }

  /// The attempt timeouts passed with each request.
  var timeouts: [Duration?] { self.state.withLock { $0.timeouts } }

  /// The number of replies not yet consumed.
  var pendingReplies: Int { self.state.withLock { $0.replies.count } }

  func send(_ request: HTTPRequest, timeout: Duration?) async throws -> HTTPResponse {
    let reply = self.state.withLock { state -> Reply? in
      state.requests.append(request)
      state.timeouts.append(timeout)
      return state.replies.isEmpty ? nil : state.replies.removeFirst()
    }
    switch reply {
    case .response(let response): return response
    case .error(let error): throw error
    case nil: throw RequestError.malformedResponse("FakeHTTPTransport: no reply queued")
    }
  }

  /// Creates a client that sends through this transport, without sleeping between retries.
  func client(
    projectID: String = "test-project",
    location: String? = nil,
    retryPolicy: (any RetryPolicy)? = nil
  ) -> BigQueryClient {
    BigQueryClient(projectID: projectID, location: location, transport: self.transport(retryPolicy))
  }

  /// Creates a transport over this fake, without sleeping between retries.
  func transport(_ retryPolicy: (any RetryPolicy)? = nil) -> BigQueryTransport {
    let options = ClientOptions().with {
      $0.retryPolicy = retryPolicy ?? BigQueryRetryPolicy.defaultPolicy
    }
    return BigQueryTransport(http: self, clientOptions: options, sleep: { _ in })
  }
}

extension HTTPRequest {
  /// The request path, or `nil` for absolute URLs.
  var path: String? {
    if case .path(let path) = self.target { return path }
    return nil
  }

  /// The value of the query parameter `name`.
  func queryValue(_ name: String) -> String? {
    self.query.first { $0.name == name }?.value
  }

  /// The body parsed as a JSON object.
  func jsonBody() throws -> [String: Any] {
    guard let body = self.body,
      let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return [:] }
    return object
  }
}
