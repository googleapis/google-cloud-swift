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
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum WriteObjectError: Error, Sendable {
  /// GCS returned an unexpected response.
  case unexpectedServerResponse(statusCode: Int, message: String)

  /// Internal error in the upload library.
  case internalError(String)

  /// The range header returned by GCS is invalid.
  case invalidRangeHeader(String)

  /// A request or service error occurred during the write operation.
  case requestError(RequestError)

  /// An error occurred while reading from or seeking the write object source.
  case sourceError(any Error)

  package static func fromSourceError(_ error: any Error) -> WriteObjectError {
    if let writeError = error as? WriteObjectError {
      return writeError
    }
    return .sourceError(error)
  }
}
