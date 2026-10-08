// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or expressed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

public import GoogleGax

/// Errors thrown by the write object API.
///
/// `WriteObjectError` is thrown by `StorageClient.writeObject(_:to:as:options:)` and its
/// overloads when an object upload fails due to a service error, transport interruption, local
/// data source failure, or unrecoverable resumption state.
///
/// For end-to-end error handling patterns and recovery strategies, see <doc:Troubleshooting>.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum WriteObjectError: Error, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// Cloud Storage returned an unexpected HTTP status code or response during upload.
  ///
  /// ## Troubleshooting
  ///
  /// This error occurs when Cloud Storage returns an unexpected HTTP status code during resumable
  /// session initiation, upload status queries, or chunk transfers, or when an HTTP 308 response
  /// reports a committed byte offset outside the valid range of bytes sent. Inspect `statusCode`
  /// and `message`, and retry the upload with a new session if the session state is corrupted.
  case unexpectedServerResponse(statusCode: Int, message: String)

  /// Internal state error in the upload library.
  ///
  /// ## Troubleshooting
  ///
  /// The most common cause of `.internalError` is attempting to resume a non-seekable
  /// ``WriteObjectSource`` (such as ``StreamSource``) when Cloud Storage reports a committed byte
  /// offset outside the currently buffered chunk window.
  ///
  /// Because a non-seekable ``WriteObjectSource`` only buffers the current in-flight chunk in
  /// memory, it cannot rewind to an earlier offset if the server lost previously acknowledged
  /// state. Whenever possible, provide a ``SeekableWriteObjectSource`` (such as ``FileSource``,
  /// ``BytesSource``, `URL`, or `Data`) so the client can seek to any server-reported offset
  /// during resumption.
  case internalError(String)

  /// The `Range` header returned by Cloud Storage in an HTTP 308 response is invalid or malformed.
  ///
  /// ## Troubleshooting
  ///
  /// Cloud Storage uses the `Range` header in HTTP 308 Resume Incomplete responses to report how
  /// many bytes have been durably committed. An invalid `Range` header typically indicates an
  /// intermediary proxy or gateway modifying HTTP headers.
  case invalidRangeHeader(String)

  /// A request or service error occurred during the write operation.
  ///
  /// ## Troubleshooting
  ///
  /// Inspect the wrapped `GoogleGax.RequestError` for the root cause:
  /// - `.service(let serviceError)`: The Cloud Storage service rejected the upload. Common status
  ///   codes include:
  ///   - `.failedPrecondition` (HTTP 412): A precondition in ``WriteObjectOptions/preconditions``
  ///     failed—for example, `ifGenerationMatch = 0` when the target object already exists, or
  ///     `ifGenerationMatch = N` when the object was concurrently overwritten.
  ///   - `.permissionDenied` (HTTP 403): Insufficient IAM permissions (`storage.objects.create`)
  ///     or a missing ``WriteObjectOptions/quotaProject`` on a Requester Pays bucket.
  ///   - `.notFound` (HTTP 404): The destination bucket does not exist, or a resumable upload
  ///     session URI expired.
  /// - `.io(let ioError)` on single-shot uploads: Uploads with a known size smaller than
  ///   ``WriteObjectOptions/resumableUploadThreshold`` (8 MB by default) use single-shot multipart
  ///   uploads. Without preconditions (`ifGenerationMatch` or `ifMetagenerationMatch`), single-shot
  ///   uploads are treated as non-idempotent and are not automatically retried on transient errors.
  ///   Supply ``StoragePreconditions`` or set ``WriteObjectOptions/idempotency`` to `true` to
  ///   enable automatic retries.
  /// - `.exhausted(let exhaustedError)`: The configured ``WriteObjectOptions/resumePolicy`` was
  ///   exhausted before the upload could finish.
  case requestError(RequestError)

  /// An error occurred while reading from or seeking the local write object source.
  ///
  /// ## Troubleshooting
  ///
  /// The upload failed because the local ``WriteObjectSource`` or ``SeekableWriteObjectSource``
  /// threw an error (such as ``WriteObjectSourceError/readFailed(underlyingError:)`` when reading
  /// a local file or stream, or ``WriteObjectSourceError/offsetOutOfBounds(offset:size:)`` if the
  /// local file was truncated while an upload was in progress). Inspect the wrapped error for the
  /// underlying file system or stream failure.
  case sourceError(any Error)

  package static func fromSourceError(_ error: any Error) -> WriteObjectError {
    if let writeError = error as? WriteObjectError {
      return writeError
    }
    return .sourceError(error)
  }

  public var description: String {
    switch self {
    case .unexpectedServerResponse(let statusCode, let message):
      return "Unexpected server response with status code \(statusCode): \(message)"
    case .internalError(let message):
      return "Internal error in upload library: \(message)"
    case .invalidRangeHeader(let header):
      return "Invalid range header: '\(header)'"
    case .requestError(let error):
      return "\(error)"
    case .sourceError(let error):
      return "Source error: \(error)"
    }
  }

  public var debugDescription: String {
    switch self {
    case .unexpectedServerResponse(let statusCode, let message):
      return
        "WriteObjectError.unexpectedServerResponse(statusCode: \(statusCode), message: \(String(reflecting: message)))"
    case .internalError(let message):
      return "WriteObjectError.internalError(\(String(reflecting: message)))"
    case .invalidRangeHeader(let header):
      return "WriteObjectError.invalidRangeHeader(\(String(reflecting: header)))"
    case .requestError(let error):
      return "WriteObjectError.requestError(\(String(reflecting: error)))"
    case .sourceError(let error):
      return "WriteObjectError.sourceError(\(String(reflecting: error)))"
    }
  }
}
