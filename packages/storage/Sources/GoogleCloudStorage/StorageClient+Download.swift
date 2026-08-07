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

extension StorageClient {
  /// Reads (downloads) an object from Cloud Storage as an async sequence of Data chunks.
  ///
  /// - Parameters:
  ///   - bucket: The GCS bucket name.
  ///   - object: The GCS object name.
  ///   - options: Configuration options for the read operation.
  /// - Returns: A `ReadObjectResult` containing initial object metadata and streaming body sequence.
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions = .init()
  ) async throws -> ReadObjectResult {
    fatalError("Unimplemented")
  }
}
