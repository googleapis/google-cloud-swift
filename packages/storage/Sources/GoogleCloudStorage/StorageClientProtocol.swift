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

/// Protocol defining the high-level object data-plane operations.
public protocol StorageClientProtocol {
  /// Core upload method accepting any upload source.
  func upload(
    _ source: some UploadSource,
    to bucket: String,
    as objectName: String,
    options: UploadOptions
  ) -> UploadTask

  /// Resumes a previously interrupted file upload using a saved upload ID (Session URI).
  func resumeUpload(
    _ source: some SeekableUploadSource,
    uploadId: String,
    options: UploadOptions
  ) -> UploadTask

  /// Convenience upload method for a local file URL.
  func upload(
    _ fileURL: URL,
    to bucket: String,
    as objectName: String,
    options: UploadOptions
  ) -> UploadTask

  /// Convenience upload method for in-memory Data.
  func upload(
    _ data: Data,
    to bucket: String,
    as objectName: String,
    options: UploadOptions
  ) -> UploadTask

  /// Reads (downloads) an object from Cloud Storage as an async sequence of Data chunks.
  func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions
  ) async throws -> ReadObjectResult
}
