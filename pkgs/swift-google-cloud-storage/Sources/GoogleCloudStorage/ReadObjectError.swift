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

public import GoogleGax

/// Errors thrown by object read and download operations.
///
/// `ReadObjectError` is thrown when awaiting ``ReadObjectHandleProtocol/metadata`` or iterating
/// over ``ReadObjectHandleProtocol/body`` on the handle returned by
/// ``StorageClient/readObject(from:object:options:)``.
///
/// For end-to-end error handling patterns and recovery strategies, see <doc:Troubleshooting>.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum ReadObjectError: Error, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The downloaded payload checksum did not match the expected checksum.
  ///
  /// ## Troubleshooting
  ///
  /// When ``ReadObjectOptions/checksums`` is enabled (the default verifies CRC32C against server
  /// metadata), the client computes a running digest as ``ByteChunk`` chunks are yielded and
  /// validates it upon reaching the end of the stream.
  ///
  /// A mismatch indicates either:
  /// - Data corruption occurred in transit. Discard the downloaded data and retry the read.
  /// - You supplied a pre-computed checksum via ``ChecksumOptions`` (`.value(...)`) that does not
  ///   match the stored object content. Verify the expected Base64 or `UInt32` digest.
  case checksumMismatch(expected: String, actual: String, algorithm: String)

  /// The range header returned by Cloud Storage is invalid or malformed.
  ///
  /// ## Troubleshooting
  ///
  /// Cloud Storage returned an HTTP `Content-Range` header that could not be parsed according to
  /// RFC 9110. This is typically caused by an intermediary proxy or gateway modifying response
  /// headers. Check your network proxy configuration or custom endpoint settings.
  case invalidRangeHeader(String)

  /// Transparent download auto-resumption failed after a network interruption.
  ///
  /// ## Troubleshooting
  ///
  /// After receiving `bytesReceived` bytes of the object payload, the stream was interrupted by
  /// `underlyingError` and the configured ``ReadObjectOptions/resumePolicy`` decided not to resume
  /// (for example, because consecutive error limits were exhausted).
  ///
  /// To recover:
  /// - Increase the resume limits on ``ReadObjectOptions/resumePolicy`` (such as
  ///   `StorageResumePolicy<ReadObjectDetails>.unbounded().stopOnConsecutiveErrors(5)`).
  /// - Manually resume the download from `bytesReceived` using
  ///   `ReadObjectRange(fromOffset: bytesReceived)` and pinning ``ReadObjectOptions/generation``
  ///   to the generation from ``ReadObjectHandleProtocol/metadata`` so you continue reading the
  ///   exact same object revision.
  case resumeFailed(bytesReceived: UInt64, underlyingError: RequestError)

  /// Cloud Storage returned an unexpected HTTP status code or error response during download.
  ///
  /// ## Troubleshooting
  ///
  /// The server returned a non-2xx HTTP status code that could not be decoded as a standard
  /// `RequestError`. Inspect `statusCode` and `message` for details from the HTTP layer or
  /// intermediary proxy.
  case unexpectedServerResponse(statusCode: Int, message: String)

  /// A request or service error occurred during the read operation.
  ///
  /// ## Troubleshooting
  ///
  /// Inspect the wrapped `GoogleGax.RequestError` for the root cause:
  /// - `.service(let serviceError)`: The Cloud Storage service rejected the request. Common status
  ///   codes include `.notFound` (HTTP 404, missing bucket or object), `.failedPrecondition`
  ///   (HTTP 412, ``StoragePreconditions`` such as `ifGenerationMatch` did not match),
  ///   `.permissionDenied` (HTTP 403, insufficient IAM permissions or missing
  ///   ``ReadObjectOptions/quotaProject`` on a Requester Pays bucket), and `.invalidArgument`
  ///   (HTTP 400, invalid ``CustomerEncryptionKeyOptions`` or request parameters).
  /// - `.exhausted(let exhaustedError)`: The initial request failed repeatedly and exhausted the
  ///   resume policy before any response headers were received.
  /// - `.http(let httpDetails)` or `.io(let ioError)`: A transport-level error occurred.
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
}
