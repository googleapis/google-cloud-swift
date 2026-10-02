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

/// Represents an error while trying to make a request to Google Cloud.
///
/// Requests to Google Cloud may fail for a number of reasons: the application may have configured
/// an invalid endpoint, the network may experience a temporary problem, there may be problems
/// trying to create the authentication tokens, or the service may reject the request, to name just
/// a few.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum RequestError: Error, Sendable {
  /// Cannot construct the URL path to send the request.
  ///
  /// ## Troubleshooting
  ///
  /// The most common cause for this error is to leave some critical field or fields in the request
  /// uninitialized or initialized to a value that produces invalid URL.
  ///
  /// Review the fields in your request object, which field is causing the problem varies by service
  /// and request, but the most common are `parent`, and `name`.
  case binding(BindingError)

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

  /// The retry or polling policy is exhausted before the operation could complete.
  ///
  /// ## Troubleshooting
  ///
  /// You have configured a retry or polling policy with a limit (such as a time limit or attempt
  /// count), which expired before the operation could complete. Increase the policy limit as
  /// needed. Rarely, the CPU in your machine is overloaded and the task was suspended before the
  /// request could be sent. Review your application deployment and CPU requirements to match the
  /// needs of your application.
  indirect case exhausted(PolicyExhaustedError)

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

  /// The client is configured with an invalid URL.
  ///
  /// ## Troubleshooting
  ///
  /// Typically, this indicates an invalid URL in the client's endpoint. The client library is
  /// unable to form a valid HTTP request. Review how you configured the client.
  case badURL(String)
}

/// The details for ``RequestError/http(_:)``.
public struct HTTPDetails: Sendable {
  /// The HTTP status code.
  public let statusCode: Int

  /// The HTTP headers.
  public let headers: HTTPHeaders

  /// The contents of the HTTP error response.
  public let payload: Data

  /// Create a new `HTTPDetails`.
  public init(
    statusCode: Int,
    headers: HTTPHeaders = HTTPHeaders(),
    payload: Data = Data()
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.payload = payload
  }
}

extension HTTPDetails: Equatable {}

extension HTTPDetails: CustomStringConvertible {
  public var description: String {
    "HTTP status \(statusCode)"
  }
}

extension HTTPDetails: CustomDebugStringConvertible {
  public var debugDescription: String {
    var desc = "HTTPDetails(statusCode: \(statusCode), headers: \(headers)"
    if !payload.isEmpty {
      let snippet = String(decoding: payload.prefix(1024), as: UTF8.self)
      desc += ", payload: \(String(reflecting: snippet))"
    }
    desc += ")"
    return desc
  }
}

extension RequestError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .binding(let error):
      return "URL binding error: \(error.description)"
    case .io(let error):
      return "I/O error: \(error)"
    case .http(let details):
      return "HTTP error \(details.statusCode)"
    case .service(let error):
      return error.description
    case .exhausted(let error):
      return error.description
    case .unimplemented:
      return "Method unimplemented"
    case .malformedResponse(let message):
      return "Malformed response: \(message)"
    case .badURL(let url):
      return "Invalid endpoint URL: \(url)"
    }
  }
}

extension RequestError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .binding(let error):
      return "RequestError.binding(\(String(reflecting: error)))"
    case .io(let error):
      return "RequestError.io(\(String(reflecting: error)))"
    case .http(let details):
      return "RequestError.http(\(String(reflecting: details)))"
    case .service(let error):
      return "RequestError.service(\(String(reflecting: error)))"
    case .exhausted(let error):
      return "RequestError.exhausted(\(String(reflecting: error)))"
    case .unimplemented:
      return "RequestError.unimplemented"
    case .malformedResponse(let message):
      return "RequestError.malformedResponse(\"\(message)\")"
    case .badURL(let url):
      return "RequestError.badURL(\"\(url)\")"
    }
  }
}

extension RequestError: LocalizedError {
  public var errorDescription: String? {
    description
  }

  public var failureReason: String? {
    switch self {
    case .binding:
      return "The request could not be mapped to a valid URL path."
    case .io(let error):
      return "The transport failed before receiving a status code (\(error))."
    case .http(let details):
      return "The server responded with HTTP status code \(details.statusCode)."
    case .service(let error):
      let codeStr = error.code.stringValue ?? "\(error.code)"
      return "The service returned error code \(codeStr): \(error.message)"
    case .exhausted(let error):
      return error.failureReason
    case .unimplemented:
      return "The requested method is not implemented."
    case .malformedResponse(let message):
      return "The service returned a malformed response: \(message)"
    case .badURL(let url):
      return "The endpoint URL is invalid: \(url)"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .binding:
      return
        "Verify that all required fields in the request (such as 'name' or 'parent') are set and correctly formatted."
    case .io:
      return "Check network connectivity and retry the request if the operation is idempotent."
    case .http:
      return
        "Review network settings and request parameters. Examine response headers or payload for details."
    case .service:
      return "Review the error code and details, and consult the service documentation."
    case .exhausted:
      return
        "Increase the retry or polling policy limit (such as timeout duration or maximum attempt count)."
    case .unimplemented:
      return
        "If using a mock client, implement the method. Otherwise, check for client library updates."
    case .malformedResponse:
      return "Report this issue to the service team."
    case .badURL:
      return "Review and correct the endpoint URL configured for the client."
    }
  }
}

/// The details for ``RequestError/exhausted(_:)``.
public enum PolicyExhaustedError: Error, Sendable, CustomStringConvertible {
  /// The retry or polling policy exceeded its maximum elapsed time.
  case elapsedTime(maximumDuration: Duration, source: RequestError? = nil)

  /// The retry or polling policy exceeded its maximum attempt count.
  case attemptCount(maximumAttempts: Int)

  /// The last error before the policy was exhausted, if any.
  public var source: RequestError? {
    switch self {
    case .elapsedTime(_, let source):
      return source
    case .attemptCount:
      return nil
    }
  }

  public var description: String {
    switch self {
    case .elapsedTime(let maxDuration, let source):
      if let source = source {
        return
          "policy exhausted: elapsed time limit of \(maxDuration) exceeded; last error: \(source)"
      }
      return "policy exhausted: elapsed time limit of \(maxDuration) exceeded"
    case .attemptCount(let maxAttempts):
      return "policy exhausted: attempt count limit of \(maxAttempts) exceeded"
    }
  }
}

extension PolicyExhaustedError: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .elapsedTime(let maxDuration, let source):
      if let source {
        return
          "PolicyExhaustedError.elapsedTime(maximumDuration: \(maxDuration), source: \(String(reflecting: source)))"
      }
      return "PolicyExhaustedError.elapsedTime(maximumDuration: \(maxDuration))"
    case .attemptCount(let maxAttempts):
      return "PolicyExhaustedError.attemptCount(maximumAttempts: \(maxAttempts))"
    }
  }
}

extension PolicyExhaustedError: LocalizedError {
  public var errorDescription: String? {
    description
  }

  public var failureReason: String? {
    switch self {
    case .elapsedTime(let maxDuration, _):
      return "The retry or polling policy exceeded its elapsed time limit of \(maxDuration)."
    case .attemptCount(let maxAttempts):
      return "The retry or polling policy exceeded its attempt limit of \(maxAttempts)."
    }
  }

  public var recoverySuggestion: String? {
    "Increase the retry or polling policy limit (such as timeout duration or maximum attempt count)."
  }
}
