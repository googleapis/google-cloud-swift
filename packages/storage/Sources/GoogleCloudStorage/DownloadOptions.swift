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

/// Specifies a byte range for ranged reads.
public enum ReadObjectRange: Sendable, Hashable, Equatable {
  /// Read the entire object (default).
  case entire

  /// Read all bytes starting from `offset` to the end of the object (HTTP `bytes=N-`).
  case fromOffset(UInt64)

  /// Read the first `count` bytes of the object (HTTP `bytes=0-N`).
  case prefix(UInt64)

  /// Read the last `count` bytes of the object (HTTP `bytes=-N`).
  case suffix(UInt64)

  /// Read a bounded range of bytes from `start` to `end` inclusive (HTTP `bytes=start-end`).
  case bounded(start: UInt64, end: UInt64)

  /// Convenience initializer for Swift `ClosedRange<UInt64>`.
  public init(_ range: ClosedRange<UInt64>) {
    self = .bounded(start: range.lowerBound, end: range.upperBound)
  }

  /// Converts the range specification to an HTTP `Range` header value string.
  public var headerValue: String? {
    switch self {
    case .entire:
      return nil
    case .fromOffset(let offset):
      return "bytes=\(offset)-"
    case .prefix(let count):
      return count > 0 ? "bytes=0-\(count - 1)" : "bytes=0-0"
    case .suffix(let count):
      return "bytes=-\(count)"
    case .bounded(let start, let end):
      return "bytes=\(start)-\(end)"
    }
  }
}

/// Configuration options for object download (`readObject`) requests.
public struct ReadObjectOptions: Sendable {
  /// Object generation (`UInt64?`) to read a specific revision of an object.
  public var generation: UInt64?

  /// Preconditions to ensure operations execute only when condition constraints pass.
  public var preconditions: StoragePreconditions?

  /// Options for Customer-Supplied Encryption Keys (CSEK).
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?

  /// Byte range for partial/ranged reads. Defaults to `.entire`.
  public var range: ReadObjectRange = .entire

  /// Flag to enable automatic decompressive transcoding by GCS. Defaults to `true`.
  public var enableDecompressiveTranscoding: Bool = true

  /// Configuration options for download checksum validation.
  public var checksums: ChecksumOptions = .default

  /// Flag to enable transparent auto-resumption on transient network failures. Defaults to `true`.
  public var autoResume: Bool = true

  /// Default configuration options.
  public static var `default`: ReadObjectOptions { ReadObjectOptions() }

  /// Creates a new `ReadObjectOptions` instance.
  public init() {}

  /// Builder pattern helper to modify configuration in place.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Metadata attributes for an object returned in response headers during a download.
public struct ReadObjectMetadata: Sendable, Hashable, Equatable {
  /// Name of the bucket containing the object.
  public var bucket: String = ""

  /// Name of the object.
  public var object: String = ""

  /// Content size of the object payload in bytes.
  public var size: Int64 = 0

  /// Generation revision number of the object.
  public var generation: Int64 = 0

  /// Metageneration revision number of the object metadata.
  public var metageneration: Int64?

  /// HTTP ETag representing the object's entity state.
  public var etag: String?

  /// Base64-encoded CRC32C checksum of the object content.
  public var crc32c: String?

  /// Base64-encoded MD5 hash of the object content.
  public var md5Hash: String?

  /// Content-Type MIME type of the object data (e.g., "text/plain", "image/png").
  public var contentType: String?

  /// Content-Encoding header of the object data (e.g., "gzip").
  public var contentEncoding: String?

  /// Content-Disposition header of the object data (e.g., "inline", "attachment; filename=...").
  public var contentDisposition: String?

  /// Storage class of the object (e.g., "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE").
  public var storageClass: String?

  /// Modification timestamp of the object.
  public var updated: Date?

  /// Creates a new `ReadObjectMetadata` instance.
  public init() {}

  /// Builder pattern helper to modify configuration in place.
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// An asynchronous sequence of `Data` chunks representing an object payload being downloaded.
public struct ReadObjectSequence: AsyncSequence, Sendable {
  public typealias Element = Data

  /// Name of the bucket containing the object being read.
  public let bucket: String

  /// Name of the object being read.
  public let object: String

  /// Configuration options used for this object download.
  public let options: ReadObjectOptions

  /// Creates a new `ReadObjectSequence` instance.
  public init(
    bucket: String,
    object: String,
    options: ReadObjectOptions = .init()
  ) {
    self.bucket = bucket
    self.object = object
    self.options = options
  }

  /// An asynchronous iterator for iterating over chunks of downloaded object payload data.
  public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
    public typealias Element = Data

    /// Advances to the next `Data` chunk in the downloaded object payload stream.
    public mutating func next() async throws -> Data? {
      // Stub implementation
      return nil
    }
  }

  /// Creates an asynchronous iterator for iterating over object payload chunks.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator()
  }
}

/// Container object returned by `readObject` containing metadata and the streaming body sequence.
public struct ReadObjectResult: Sendable {
  /// Object metadata extracted from initial HTTP response headers.
  public let metadata: ReadObjectMetadata

  /// Asynchronous sequence yielding chunks of binary data payload.
  public let body: ReadObjectSequence

  /// Creates a new `ReadObjectResult` instance.
  public init(metadata: ReadObjectMetadata, body: ReadObjectSequence) {
    self.metadata = metadata
    self.body = body
  }
}
