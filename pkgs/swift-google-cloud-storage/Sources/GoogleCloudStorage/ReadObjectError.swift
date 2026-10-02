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
public import GoogleGax

/// Errors thrown by object read and download operations.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum ReadObjectError: Error, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, LocalizedError
{
  /// The downloaded payload checksum did not match the expected checksum.
  case checksumMismatch(expected: String, actual: String, algorithm: String)

  /// The range header returned by Cloud Storage is invalid or malformed.
  case invalidRangeHeader(String)

  /// Transparent download auto-resumption failed after a network interruption.
  case resumeFailed(bytesReceived: UInt64, underlyingError: RequestError)

  /// Cloud Storage returned an unexpected HTTP status code or error response during download.
  case unexpectedServerResponse(statusCode: Int, message: String)

  /// A request or service error occurred during the read operation.
  case requestError(RequestError)

  public var description: String {
    switch self {
    case .checksumMismatch(let expected, let actual, let algorithm):
      return "Checksum mismatch using \(algorithm): expected '\(expected)', got '\(actual)'"
    case .invalidRangeHeader(let header):
      return "Invalid range header: '\(header)'"
    case .resumeFailed(let bytesReceived, let underlyingError):
      return "Resume download failed after receiving \(bytesReceived) bytes: \(underlyingError)"
    case .unexpectedServerResponse(let statusCode, let message):
      return "Unexpected server response with status code \(statusCode): \(message)"
    case .requestError(let error):
      return "\(error)"
    }
  }

  public var debugDescription: String {
    switch self {
    case .checksumMismatch(let expected, let actual, let algorithm):
      return
        "ReadObjectError.checksumMismatch(expected: \(String(reflecting: expected)), actual: \(String(reflecting: actual)), algorithm: \(String(reflecting: algorithm)))"
    case .invalidRangeHeader(let header):
      return "ReadObjectError.invalidRangeHeader(\(String(reflecting: header)))"
    case .resumeFailed(let bytesReceived, let underlyingError):
      return
        "ReadObjectError.resumeFailed(bytesReceived: \(bytesReceived), underlyingError: \(String(reflecting: underlyingError)))"
    case .unexpectedServerResponse(let statusCode, let message):
      return
        "ReadObjectError.unexpectedServerResponse(statusCode: \(statusCode), message: \(String(reflecting: message)))"
    case .requestError(let error):
      return "ReadObjectError.requestError(\(String(reflecting: error)))"
    }
  }

  public var errorDescription: String? {
    switch self {
    case .requestError(let error):
      return (error as? LocalizedError)?.errorDescription ?? description
    default:
      return description
    }
  }

  public var failureReason: String? {
    switch self {
    case .checksumMismatch:
      return "The downloaded data checksum did not match the expected value."
    case .invalidRangeHeader:
      return "The range header returned by Cloud Storage is invalid or malformed."
    case .resumeFailed:
      return "Transparent download auto-resumption failed after a network interruption."
    case .unexpectedServerResponse:
      return "Cloud Storage returned an unexpected HTTP status code during download."
    case .requestError(let error):
      return (error as? LocalizedError)?.failureReason
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .checksumMismatch:
      return "Verify data integrity or retry the download."
    case .resumeFailed:
      return "Retry the download from the beginning."
    case .requestError(let error):
      return (error as? LocalizedError)?.recoverySuggestion
    default:
      return nil
    }
  }
}
