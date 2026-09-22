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

/// Errors thrown by `WriteObjectSource` and `SeekableWriteObjectSource` implementations.
///
/// - Note: As Google Cloud APIs and client libraries evolve, new error cases may be added to this
///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
///   clause in `switch` statements.
public enum WriteObjectSourceError: Error, Sendable {
  /// The requested seek offset exceeds the size of the source.
  case offsetOutOfBounds(offset: UInt64, size: UInt64)

  /// Reading from the underlying data source failed.
  case readFailed(underlyingError: any Error)
}

/// Represents a data source that can be read from sequentially.
public protocol WriteObjectSource: Sendable {
  /// Reads the next chunk of data, up to `maxBytes`.
  /// Returns `nil` when the source is exhausted.
  mutating func read(maxBytes: Int) async throws -> ByteChunk?

  /// The total size of the source, if known.
  var totalSize: UInt64? { get }
}

/// Represents a write object source that supports seeking (rewinding/skipping).
/// Conformance to this protocol enables persistent resumption.
public protocol SeekableWriteObjectSource: WriteObjectSource {
  /// Seeks to a specific byte offset.
  mutating func seek(to offset: UInt64) async throws
}
