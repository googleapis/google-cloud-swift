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
import struct AsyncHTTPClient.HTTPClientResponse
import NIOHTTP1

/// Represents errors occurring during an HTTP request to an authentication or token endpoint.
///
/// Captures HTTP status failures, transport and network errors, payload decoding errors, and invalid UTF-8 data
/// encountered when communicating with Google Cloud token servers, STS, or the Compute Engine metadata server.
enum AuthHTTPError: Error, Sendable {
  /// The server returned an HTTP status code outside the 200–299 range (e.g. 400, 401, 403, 429, 500, 503).
  ///
  /// Because `HTTPClientResponse.body` is a single-pass async stream that is consumed before status
  /// validation, the collected error response payload bytes are stored alongside `response` in `data`.
  case unsuccessfulResponse(response: HTTPClientResponse, data: Data = Data())

  /// A transport-level or network I/O error occurred (e.g., DNS resolution failure, connection timeout, connection reset).
  case transportError(URLError)

  /// A decoding error occurred while parsing the response payload into the expected data model.
  case decodingError(error: any Error & Sendable)

  /// An unexpected or uncategorized error occurred during request execution.
  case unknown(any Error & Sendable)

  /// Failed to decode the response body as a valid UTF-8 plain-text string.
  case invalidUTF8Response
}

extension AuthHTTPError {
  /// The underlying `URLError` if this is a transport-level error (`.transportError`), or `nil` otherwise.
  var urlError: URLError? {
    switch self {
    case .transportError(let error):
      return error
    default:
      return nil
    }
  }

  /// The HTTP status code integer if this is an unsuccessful response (`.unsuccessfulResponse`), or `nil` otherwise.
  var statusCode: UInt? {
    switch self {
    case .unsuccessfulResponse(let response, _):
      return response.status.code
    default:
      return nil
    }
  }

  /// The raw response body as a UTF-8 string if this is an unsuccessful response (`.unsuccessfulResponse`), or `nil` otherwise.
  ///
  /// Returns `nil` if the error is not `.unsuccessfulResponse` or if the response payload bytes are not valid UTF-8.
  var body: String? {
    switch self {
    case .unsuccessfulResponse(_, let data):
      return String(data: data, encoding: .utf8)
    default:
      return nil
    }
  }

  /// The raw response body data if this is an unsuccessful response (`.unsuccessfulResponse`), or `nil` otherwise.
  var bodyData: Data? {
    switch self {
    case .unsuccessfulResponse(_, let data):
      return data
    default:
      return nil
    }
  }

  /// The HTTP response headers as a string map if this is an unsuccessful response (`.unsuccessfulResponse`), or `nil` otherwise.
  var headers: [String: String]? {
    switch self {
    case .unsuccessfulResponse(let response, _):
      var result: [String: String] = [:]
      for (key, value) in response.headers {
        result[key] = value
      }
      return result
    default:
      return nil
    }
  }

  /// Indicates whether this HTTP error is transient and eligible for retry.
  ///
  /// Server errors (HTTP status >= 500), rate limiting (HTTP 429), request timeouts (HTTP 408),
  /// transport errors, and unknown errors are considered transient and retryable. Client errors
  /// (other 4xx statuses) and payload decoding errors are considered permanent.
  var isRetryable: Bool {
    switch self {
    case .unsuccessfulResponse(let response, _):
      let status = response.status.code
      return status >= 500 || status == 429 || status == 408
    case .decodingError, .invalidUTF8Response:
      return false
    case .transportError, .unknown:
      return true
    }
  }

  /// Evaluates whether an error encountered during a token request is transient and eligible for retry.
  ///
  /// Unwraps `CredentialsError.cannotFetchToken` to evaluate the underlying error when invoked by `TokenCache`,
  /// and treats other `CredentialsError` cases as permanent.
  ///
  /// - Parameter error: The error to evaluate.
  /// - Returns: `true` if the error is transient and should be retried; `false` if it is permanent.
  static func isRetryable(_ error: any Error) -> Bool {
    if let credentialsError = error as? CredentialsError {
      switch credentialsError {
      case .cannotFetchToken(_, let underlyingError):
        return isRetryable(underlyingError)
      case .parseError, .notSupported, .cannotLoadFile:
        return false
      }
    }
    if let authError = error as? AuthHTTPError {
      return authError.isRetryable
    }
    return true
  }
}

extension AuthHTTPError: CustomStringConvertible {
  /// Maximum number of response body bytes formatted in error descriptions.
  static let maxBodyPreviewBytes = 1024

  var description: String {
    switch self {
    case .unsuccessfulResponse(let response, let data):
      if data.isEmpty {
        return "HTTP status \(response.status.code)"
      }
      let snippet = String(decoding: data.prefix(Self.maxBodyPreviewBytes), as: UTF8.self)
      return "HTTP status \(response.status.code): \(snippet)"
    case .transportError(let error):
      return "Transport error: \(error)"
    case .decodingError(let error):
      return "Response decoding error: \(error)"
    case .unknown(let error):
      return "Unexpected HTTP error: \(error)"
    case .invalidUTF8Response:
      return "Response body is not valid UTF-8"
    }
  }
}

extension AuthHTTPError: CustomDebugStringConvertible {
  var debugDescription: String {
    switch self {
    case .unsuccessfulResponse(let response, let data):
      var desc =
        "AuthHTTPError.unsuccessfulResponse(statusCode: \(response.status.code), headers: \(response.headers)"
      if !data.isEmpty {
        let snippet = String(decoding: data.prefix(Self.maxBodyPreviewBytes), as: UTF8.self)
        desc += ", body: \(String(reflecting: snippet))"
      }
      desc += ")"
      return desc
    case .transportError(let error):
      return "AuthHTTPError.transportError(\(String(reflecting: error)))"
    case .decodingError(let error):
      return "AuthHTTPError.decodingError(\(String(reflecting: error)))"
    case .unknown(let error):
      return "AuthHTTPError.unknown(\(String(reflecting: error)))"
    case .invalidUTF8Response:
      return "AuthHTTPError.invalidUTF8Response: \(description)"
    }
  }
}
