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
  case unsuccessfulResponse(response: HTTPClientResponse)

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
    case .unsuccessfulResponse(let response):
      return response.status.code
    default:
      return nil
    }
  }

  /// The raw response body as a UTF-8 string if this is an unsuccessful response or a decoding error.
  var body: String? {
    switch self {
    case .unsuccessfulResponse(_):
      // TODO(#81) - return the body
      return nil
    case .decodingError(_):
      return nil
    default:
      return nil
    }
  }

  /// The raw response body data if this is an unsuccessful response or a decoding error.
  var bodyData: Data? {
    switch self {
    case .unsuccessfulResponse(_):
      // TODO(#81) - return the data, if any.
      return nil
    case .decodingError(_):
      return nil
    default:
      return nil
    }
  }

  /// The HTTP response headers as a string map if this is an unsuccessful response (`.unsuccessfulResponse`), or `nil` otherwise.
  var headers: [String: String]? {
    switch self {
    case .unsuccessfulResponse(let response):
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
    case .unsuccessfulResponse(let response):
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
