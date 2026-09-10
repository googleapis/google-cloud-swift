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
import GoogleRpc

/// The details for ``RequestError/service(_:)``.
public struct ServiceError: Sendable {
  /// The status code.
  public let code: GoogleRpc.Code
  /// The error message.
  public let message: String
  /// The error details, if any
  public let details: [StatusDetail]
  /// The HTTP status code, if known.
  public let httpStatusCode: Int?

  /// Create a new `ServiceError`.
  public init(
    code: GoogleRpc.Code,
    message: String,
    details: [StatusDetail] = []
  ) {
    self.init(code: code, message: message, details: details, httpStatusCode: nil)
  }

  /// Create a new `ServiceError`.
  public init(
    code: GoogleRpc.Code,
    message: String,
    details: [StatusDetail] = [],
    httpStatusCode: Int?
  ) {
    self.code = code
    self.message = message
    self.details = details
    self.httpStatusCode = httpStatusCode
  }
}

extension GoogleRpc.Code {
  /// Maps an HTTP status code to the corresponding canonical `GoogleRpc.Code`.
  public init(httpStatusCode: Int) {
    switch httpStatusCode {
    case 200...299:
      self = .ok
    case 400:
      self = .invalidArgument
    case 401:
      self = .unauthenticated
    case 403:
      self = .permissionDenied
    case 404:
      self = .notFound
    case 409:
      self = .alreadyExists
    case 412:
      self = .failedPrecondition
    case 429:
      self = .resourceExhausted
    case 499:
      self = .cancelled
    case 500:
      self = .internal
    case 501:
      self = .unimplemented
    case 503:
      self = .unavailable
    case 504:
      self = .deadlineExceeded
    default:
      self = .unknown
    }
  }

  /// Maps a canonical `GoogleRpc.Code` to the corresponding HTTP status code.
  public var httpStatusCode: Int {
    switch self {
    case .ok: return 200
    case .cancelled: return 499
    case .unknown: return 500
    case .invalidArgument: return 400
    case .deadlineExceeded: return 504
    case .notFound: return 404
    case .alreadyExists: return 409
    case .permissionDenied: return 403
    case .resourceExhausted: return 429
    case .failedPrecondition: return 412
    case .aborted: return 409
    case .outOfRange: return 400
    case .unimplemented: return 501
    case .internal: return 500
    case .unavailable: return 503
    case .dataLoss: return 500
    case .unauthenticated: return 401
    default: return 500
    }
  }
}
