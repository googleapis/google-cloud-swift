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

/// Represents any error occurring during an authentication HTTP request.
enum AuthHTTPError: Error, Sendable {
  /// The server returned a non-2xx status code.
  case unsuccessfulResponse(response: HTTPClientResponse)
  /// A transport-level error occurred (e.g., timeout, connection lost).
  case transportError(URLError)
  /// A decoding error occurred while parsing the response.
  case decodingError(error: any Error & Sendable)
  /// An unexpected or unknown error occurred.
  case unknown(any Error & Sendable)
  /// Failed to decode the response body as a UTF-8 string.
  case invalidUTF8Response
}

extension AuthHTTPError {
  /// The underlying URLError if this is a transport-level error.
  var urlError: URLError? {
    switch self {
    case .transportError(let error):
      return error
    default:
      return nil
    }
  }

  /// The HTTP status code if this is an unsuccessful response.
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

  /// The HTTP response headers as a string map if this is an unsuccessful response.
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
}
