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

import Foundation

/// Errors thrown by the upload API.
public enum UploadError: Error, Sendable {
  /// The local source is smaller than the offset reported by GCS.
  /// Indicates the source was modified or truncated.
  case localSourceTooSmall(localSize: Int64, gcsOffset: Int64)

  /// The resumable session has expired (usually after 7 days) or was not found.
  case sessionExpired(uploadId: String, underlyingError: Error?)

  /// The upload was cancelled by the user.
  case cancelled

  /// GCS returned an unexpected response.
  case unexpectedServerResponse(statusCode: Int, message: String)

  /// Network error during upload.
  case networkError(underlyingError: Error)

  /// Internal error in the upload library.
  case internalError(String)

  /// The range header returned by GCS is invalid.
  case invalidRangeHeader(String)
}
