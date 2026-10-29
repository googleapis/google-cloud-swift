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
  ///
  /// Thrown after HTTP 200–299 status validation succeeds. Raw response bytes are intentionally omitted
  /// from this case so partially-malformed 2xx token responses cannot expose live `access_token` or
  /// `id_token` values in error messages.
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

// MARK: - Error Formatting

// `AuthHTTPError` is `internal` to `GoogleAuth`, but token providers wrap it as `underlyingError`
// inside `public enum CredentialsError.cannotFetchToken(message:underlyingError:)`. External callers
// cannot downcast `underlyingError`, so `CredentialsError.description` and `debugDescription` rely on
// these conformances instead of Swift's default enum reflection (which formats `Data` as `"<N> bytes"`
// and dumps `HTTPClientResponse` internals).
//
// Security note: Neither `description` nor `debugDescription` includes HTTP response headers or raw
// response bodies, which could carry session cookies, auth headers, or credentials echoed by proxies
// or misconfigured endpoints. Instead, `.unsuccessfulResponse` decodes only allowlisted fields from
// standard OAuth 2.0 / STS and Google Cloud `google.rpc.Status` JSON error responses, ignoring all
// other fields and non-JSON payloads.
extension AuthHTTPError: CustomStringConvertible {
  /// Maximum UTF-8 byte length of a decoded error code or message included in formatted errors.
  static let maxErrorMessageBytes = 1024

  /// Upper bound on payload size considered when attempting structured JSON error extraction.
  ///
  /// Standard OAuth 2.0 and Google RPC error payloads are well under a few kilobytes; skipping larger
  /// payloads avoids unnecessary JSON parsing work on large HTML error pages.
  static let maxStructuredErrorPayloadBytes = 16 * 1024

  var description: String {
    switch self {
    case .unsuccessfulResponse(let response, let data):
      let statusCode = response.status.code
      guard let detail = Self.structuredErrorDetail(from: data) else {
        return "HTTP status \(statusCode)"
      }
      switch (detail.code, detail.message) {
      case (let code?, let message?):
        return "HTTP status \(statusCode) (\(code)): \(message)"
      case (let code?, nil):
        return "HTTP status \(statusCode) (\(code))"
      case (nil, let message?):
        return "HTTP status \(statusCode): \(message)"
      case (nil, nil):
        return "HTTP status \(statusCode)"
      }
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
      var desc = "AuthHTTPError.unsuccessfulResponse(statusCode: \(response.status.code)"
      if let detail = Self.structuredErrorDetail(from: data) {
        if let code = detail.code {
          desc += ", error: \(String(reflecting: code))"
        }
        if let message = detail.message {
          desc += ", message: \(String(reflecting: message))"
        }
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

extension AuthHTTPError {
  /// Allowlisted diagnostic fields extracted from a structured JSON error payload.
  private struct StructuredErrorDetail {
    let code: String?
    let message: String?
  }

  /// RFC 6749 §5.2 OAuth 2.0 and RFC 8693 §2.2.2 STS error response schema
  /// (returned by `oauth2.googleapis.com/token` and `sts.googleapis.com/v1/token`).
  private struct OAuthErrorPayload: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
      case error
      case errorDescription = "error_description"
    }
  }

  /// Google Cloud REST error envelope (`google.rpc.Status`, returned by IAM Credentials and Google APIs).
  private struct GoogleRPCErrorEnvelope: Decodable {
    struct StatusBody: Decodable {
      let status: String?
      let message: String?
    }

    let error: StatusBody
  }

  /// Attempts to extract allowlisted error code and message strings from known Google auth JSON
  /// error schemas, returning `nil` for empty, oversized, non-JSON, or unrecognized payloads.
  private static func structuredErrorDetail(from data: Data) -> StructuredErrorDetail? {
    guard !data.isEmpty, data.count <= Self.maxStructuredErrorPayloadBytes else {
      return nil
    }

    let decoder = JSONDecoder()

    if let oauth = try? decoder.decode(OAuthErrorPayload.self, from: data) {
      let code = Self.normalizedErrorField(oauth.error)
      let message = Self.normalizedErrorField(oauth.errorDescription)
      if code != nil || message != nil {
        return StructuredErrorDetail(code: code, message: message)
      }
    }

    if let rpc = try? decoder.decode(GoogleRPCErrorEnvelope.self, from: data) {
      let code = Self.normalizedErrorField(rpc.error.status)
      let message = Self.normalizedErrorField(rpc.error.message)
      if code != nil || message != nil {
        return StructuredErrorDetail(code: code, message: message)
      }
    }

    return nil
  }

  /// Trims surrounding whitespace and bounds `value` to `maxErrorMessageBytes` UTF-8 bytes,
  /// returning `nil` if the trimmed string is empty.
  private static func normalizedErrorField(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return Self.truncateUTF8(trimmed, maxBytes: Self.maxErrorMessageBytes)
  }

  /// Truncates `string` to at most `maxBytes` UTF-8 bytes without splitting multi-byte `Character`
  /// clusters.
  private static func truncateUTF8(_ string: String, maxBytes: Int) -> String {
    if string.utf8.count <= maxBytes {
      return string
    }
    var endIndex = string.startIndex
    var byteCount = 0
    for index in string.indices {
      let nextIndex = string.index(after: index)
      let charBytes = string.utf8.distance(from: index, to: nextIndex)
      if byteCount + charBytes > maxBytes {
        break
      }
      byteCount += charBytes
      endIndex = nextIndex
    }
    return String(string[..<endIndex])
  }
}
