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

/// Errors thrown by object read and download operations.
public enum DownloadError: Error, Sendable, Equatable {
  /// The downloaded payload checksum did not match the expected checksum.
  case checksumMismatch(expected: String, actual: String, algorithm: String)

  /// The range header returned by Cloud Storage is invalid or malformed.
  case invalidRangeHeader(String)

  /// Transparent download auto-resumption failed after a network interruption.
  case resumeFailed(bytesReceived: UInt64, message: String)

  /// Cloud Storage returned an unexpected HTTP status code or error response during download.
  case unexpectedServerResponse(statusCode: Int, message: String)
}
