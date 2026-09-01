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
import NIOCore

/// Represents a data source that can be read from sequentially.
public protocol UploadSource: Sendable {
  /// Reads the next chunk of data, up to `maxBytes`.
  /// Returns `nil` when the source is exhausted.
  mutating func read(maxBytes: Int) async throws -> ByteBuffer?

  /// The total size of the source, if known.
  var totalSize: Int64? { get }
}

/// Represents an upload source that supports seeking (rewinding/skipping).
/// Conformance to this protocol enables persistent resumption.
public protocol SeekableUploadSource: UploadSource {
  /// Seeks to a specific byte offset.
  mutating func seek(to offset: Int64) async throws
}
