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

/// Represents an error while trying to make a request to Google Cloud.
///
/// Requests to Google Cloud may fail for a number of reasons: the application may have configured
/// an invalid endpoint, the network may experience a temporary problem, there may be problems
/// trying to create the authentication tokens, or the service may reject the request, to name just
/// a few.
public enum RequestError: Error {
  /// Cannot construct the URL path to send the request.
  ///
  /// ## Troubleshooting
  ///
  /// The most common cause for this error is to leave some critical field or fields in the request
  /// uninitialized or initialized to a value that produces invalid URL.
  ///
  /// Review the fields in your request object, which field is causing the problem varies by service
  /// and request, but the most common are `parent`, and `name`.
  case binding(String)

  /// The HTTP transport returned an unexpected response type.
  ///
  /// ## Troubleshooting
  ///
  /// The client libraries expect `HTTPURLResponse` as responses from the `URLSession` calls. The
  /// most common cause for this error is using an `ftp`, or `file` endpoint that just happens to
  /// work.
  case badResponseType

  /// The request failed with some type of I/O error, before getting a status code.
  ///
  /// ## Troubleshooting
  ///
  /// This indicates that the transport failed before getting a status code. For example, because
  /// the connection was interrupted.
  ///
  /// This is an unavoidable problem in distributed systems. The remote service (or load balancers)
  /// may restart, the network elements may fail, the kernel may run out of resources for
  /// networking, and so on. The client library automatically retries these errors **if** the
  /// operation isidempotent. For non-idempotent operations, it is unsafe to retry the request and
  /// the application must handle the error.
  case io(any Error)

  /// The HTTP transport failed before getting a full error from the service.
  ///
  /// ## Troubleshooting
  ///
  /// This indicates that an HTTP request returned a error status code, but the payload was not a valid service error.
  /// Google Cloud services are behind load balancers and/or proxy servers. These may return HTTP errors before the
  /// request makes it to the Google Cloud service.
  ///
  /// Review your network settings and the request fields. Also examine the response, sometimes it contains information
  /// in human readable form.
  case http(HTTPDetails)

  /// The service returned a well-formed error response.
  ///
  /// ## Troubleshooting
  ///
  /// Check the error type, error message, and error details. Then consult the documentation for the service.
  case service(ServiceError)

  /// The retry policy is exhausted before sending a request.
  ///
  /// ## Troubleshooting
  ///
  /// You have configured a retry policy with a time limit (generally a good idea), which expired
  /// before any request was sent. Most likely the retry policy time limit is too short. Increase
  /// the policy time limit as needed. Rarely, the CPU in your machine is overloaded and the task
  /// was suspended before the request could be sent. Review your application deployment and CPU
  /// requirements to match the needs of your application.
  indirect case exhausted(LimitedElapsedTimeError)

  /// The method is not implemented.
  ///
  /// ## Troubleshooting
  ///
  /// You probably called a method in a mock client and forgot to implement the method in the mock.
  ///
  /// To support mocking, the clients are classes that conform to a protocol. To avoid breaking changes when the
  /// protocol gains new methods, the protocol throws this exception by default. The clients in the client library
  /// always implement all the methods. The most common reason for this error is to miss (and use) a method in a mocked
  /// client. If this is not the case, then the client library has a serious bug, please open an issue at
  /// <https://github.com/googleapis/google-cloud-swift/issues>.
  case unimplemented

  /// The service returned a response that is missing required fields or is otherwise malformed.
  ///
  /// ## Troubleshooting
  ///
  /// This indicates a bug in the service. The service returned a response that does not match the
  /// API contract. For example, a long-running operation completed but did not contain either a
  /// success response or an error details.
  ///
  /// Report this issue to the service team.
  case malformedResponse(String)
}

/// The details for ``RequestError/http(_:)``.
public struct HTTPDetails: Sendable {
  /// The HTTP status code.
  public let http_status_code: Int

  /// The HTTP headers.
  public let headers: [String: String]

  /// The contents of the HTTP error response.
  public let payload: Data

  /// Create a a new `HTTPDetails`.
  public init(
    http_status_code: Int,
    headers: [String: String],
    payload: Data = Data()
  ) {
    self.http_status_code = http_status_code
    self.headers = headers
    self.payload = payload
  }
}

/// The details for ``RequestError/exhausted(_:)``.
public struct LimitedElapsedTimeError: Error, Sendable {
  /// The maximum duration allowed by the policy.
  public let maximumDuration: Duration

  /// The last error before the policy was exhausted.
  public let source: RequestError

  /// Create a new `LimitedElapsedTimeError`.
  public init(maximumDuration: Duration, source: RequestError) {
    self.maximumDuration = maximumDuration
    self.source = source
  }
}
