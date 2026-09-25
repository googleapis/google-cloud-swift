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
public import GoogleGax

/// Specifies a byte range for ranged reads.
public struct ReadObjectRange: Sendable, Hashable, Equatable {
  fileprivate enum Store: Sendable, Hashable, Equatable {
    /// Read the entire object (default).
    case entire

    /// Read zero bytes (HTTP `bytes=0-0` for metadata/headers only).
    case zero

    /// Read all bytes starting from `offset > 0` to the end of the object (HTTP `bytes=N-`).
    case fromOffset(Int64)

    /// Read the last `count > 0` bytes of the object (HTTP `bytes=-N`).
    case suffix(Int64)

    /// Read a bounded range of bytes from `range.lowerBound` to `range.upperBound` inclusive (HTTP `bytes=start-end`).
    case bounded(ClosedRange<Int64>)

    /// Converts the range specification to an HTTP `Range` header value string.
    var headerValue: String? {
      switch self {
      case .entire:
        return nil
      case .zero:
        return "bytes=0-0"
      case .fromOffset(let offset):
        return "bytes=\(offset)-"
      case .suffix(let count):
        return "bytes=-\(count)"
      case .bounded(let range):
        return "bytes=\(range.lowerBound)-\(range.upperBound)"
      }
    }
  }

  fileprivate let store: Store

  /// Returns a range representing the entire object.
  public init() {
    self.store = .entire
  }

  /// Returns a range representing the entire object.
  public static var entire: Self {
    .init()
  }

  /// Converts the range specification to an HTTP `Range` header value string.
  package var headerValue: String? {
    store.headerValue
  }

  /// Convenience initializer for Swift `ClosedRange<UInt64>`.
  public init?(range: ClosedRange<UInt64>) {
    self.init(start: range.lowerBound, end: range.upperBound)
  }

  /// Convenience initializer for Swift `PartialRangeFrom<UInt64>` (e.g. `1024...`).
  public init?(range: PartialRangeFrom<UInt64>) {
    self.init(fromOffset: range.lowerBound)
  }

  /// Convenience initializer for Swift `PartialRangeThrough<UInt64>` (e.g. `...1024`).
  public init?(range: PartialRangeThrough<UInt64>) {
    self.init(start: 0, end: range.upperBound)
  }

  /// Creates a bounded range from `start` to `end` inclusive, or returns `nil` if `end < start`.
  public init?(start: UInt64, end: UInt64) {
    guard start <= end else { return nil }
    guard let s = Int64(exactly: start) else { return nil }
    guard let e = Int64(exactly: end) else { return nil }
    self.store = .bounded(s...e)
  }

  /// Creates a range starting from the given offset.
  /// When `fromOffset` is 0, this is normalized to `.entire`.
  public init?(fromOffset: UInt64) {
    guard let o = Int64(exactly: fromOffset) else { return nil }
    guard o != 0 else {
      self.store = .entire
      return
    }
    self.store = .fromOffset(o)
  }

  /// Creates a range for the first `count` bytes of the object (HTTP `bytes=0-N`).
  public init?(prefix: UInt64) {
    guard let p = Int64(exactly: prefix) else { return nil }
    guard p != 0 else {
      self.store = .zero
      return
    }
    self.store = .bounded(0...(p - 1))
  }

  /// Creates a range for the last `count` bytes of the object (HTTP `bytes=-N`).
  public init?(suffix: UInt64) {
    guard let s = Int64(exactly: suffix) else { return nil }
    guard s != 0 else {
      self.store = .zero
      return
    }
    self.store = .suffix(s)
  }

  package var isZeroBytes: Bool {
    store == .zero
  }
}

/// Represents a parsed HTTP `Content-Range` response header.
struct HttpContentRange: Sendable, Hashable, Equatable {
  let start: UInt64
  let end: UInt64
  let totalSize: UInt64?

  init(start: UInt64, end: UInt64, totalSize: UInt64? = nil) {
    self.start = start
    self.end = end
    self.totalSize = totalSize
  }

  /// Parses an HTTP `Content-Range` header value (e.g., `"bytes 0-499/1000"`).
  static func parse(_ header: String) throws -> HttpContentRange {
    let trimmed = header.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("bytes ") else {
      throw ReadObjectError.invalidRangeHeader(header)
    }
    let spec = trimmed.dropFirst("bytes ".count).trimmingCharacters(in: .whitespaces)
    let parts = spec.split(separator: "/")
    guard parts.count == 2 else {
      throw ReadObjectError.invalidRangeHeader(header)
    }
    let rangeParts = parts[0].split(separator: "-")
    guard rangeParts.count == 2,
      let start = UInt64(rangeParts[0]),
      let end = UInt64(rangeParts[1])
    else {
      throw ReadObjectError.invalidRangeHeader(header)
    }
    guard start <= end else {
      throw ReadObjectError.invalidRangeHeader(header)
    }
    let totalSizeStr = parts[1]
    let totalSize: UInt64?
    if totalSizeStr == "*" {
      totalSize = nil
    } else if let total = UInt64(totalSizeStr) {
      totalSize = total
    } else {
      throw ReadObjectError.invalidRangeHeader(header)
    }
    return HttpContentRange(start: start, end: end, totalSize: totalSize)
  }
}

/// Configuration options for object download (`readObject`) requests.
///
/// Use `ReadObjectOptions` to customize download behaviors when calling `StorageClient.readObject(...)`.
/// Options include specifying byte ranges for partial reads, object generation revisions, preconditions,
/// Customer-Supplied Encryption Keys (CSEK), checksum validation, decompressive transcoding, and auto-resumption.
///
/// ## Configuration Styles
///
/// Configure `ReadObjectOptions` using the `.with` closure builder.
///
/// ```swift
/// if let range = ReadObjectRange(range: 0...1024) {
///   let options = ReadObjectOptions().with {
///     $0.range = range
///   }
/// }
/// ```
///
/// ## Key Configuration Features
///
/// ### Customer-Supplied Encryption Keys (CSEK)
///
/// Download objects encrypted with a Customer-Supplied Encryption Key (CSEK) by providing `CustomerEncryptionKeyOptions`:
///
/// ```swift
/// let csek = try CustomerEncryptionKeyOptions(keyBase64: "your-base64-encoded-256bit-key==")
/// let options = ReadObjectOptions().with {
///   $0.customerEncryptionKey = csek
/// }
///
/// let download = client.readObject(from: "my-bucket", object: "encrypted.bin", options: options)
/// for try await chunk in download.body {
///   // Process ByteChunk chunk
/// }
/// ```
///
/// ### Ranged Reads
///
/// Read specific byte ranges using `ReadObjectRange`:
///
/// ```swift
/// if let range = ReadObjectRange(fromOffset: 1024) {
///   let options = ReadObjectOptions().with {
///     $0.range = range // Read from byte 1024 to the end
///   }
/// }
/// ```
///
/// ### Preconditions
///
/// Apply preconditions to the download operation:
///
/// ```swift
/// let options = ReadObjectOptions().with {
///   $0.preconditions = StoragePreconditions().with {
///     $0.ifGenerationMatch = 12345
///   }
/// }
/// ```
///
/// ### Checksum Validation
///
/// Validate data integrity during downloads using CRC32C or MD5 checksums:
///
/// ```swift
/// // Default: Automatic CRC32C validation against server metadata
/// let options = ReadObjectOptions()
///
/// // Validate against a pre-computed Base64-encoded checksum
/// let options = ReadObjectOptions().with {
///   $0.checksums = ChecksumOptions(crc32c: "TVUQaA==")
/// }
///
/// // Validate against a 32-bit unsigned integer CRC32C checksum
/// let options = ReadObjectOptions().with {
///   $0.checksums = ChecksumOptions(crc32c: 0x4D551068)
/// }
///
/// // Validate using MD5 instead of CRC32C
/// let options = ReadObjectOptions().with {
///   $0.checksums = ChecksumOptions(crc32c: nil, md5: .auto)
/// }
///
/// // Validate both CRC32C and MD5
/// let options = ReadObjectOptions().with {
///   $0.checksums = ChecksumOptions(crc32c: .auto, md5: .auto)
/// }
///
/// // Disable checksum validation
/// let options = ReadObjectOptions().with {
///   $0.checksums = .none
/// }
/// ```
///
/// > Note: Automatic checksum verification (`.auto`) is skipped for partial (ranged) reads
/// > and decompressive transcoding because server metadata checksums cover the entire original
/// > object, not partial or decompressed bytes. Pre-computed expected values (`.value(...)`)
/// > are always verified.
public struct ReadObjectOptions: Sendable {
  /// Object generation (`Int64?`) to read a specific revision of an object.
  public var generation: Int64?

  /// Preconditions to ensure operations execute only when condition constraints pass.
  public var preconditions: StoragePreconditions?

  /// Options for Customer-Supplied Encryption Keys (CSEK).
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?

  /// Byte range for partial/ranged reads. Defaults to `.entire`.
  public var range: ReadObjectRange = .entire

  /// Flag to enable automatic decompressive transcoding by GCS. Defaults to `true`.
  public var enableDecompressiveTranscoding: Bool = true

  /// Configures client-side checksum validation for the downloaded object payload.
  ///
  /// By default, `.default` enables auto-validation which automatically verifies CRC32C and/or MD5
  /// checksums against the object's server metadata upon reaching EOF.
  ///
  /// If a checksum mismatch is detected, `ReadObjectError.checksumMismatch` is thrown.
  public var checksums: ChecksumOptions = .default

  /// Overrides the resume policy for this download.
  public var resumePolicy: (any ResumePolicy<ReadObjectDetails>)? = nil

  /// Overrides the backoff policy for this download.
  public var backoffPolicy: (any BackoffPolicy)? = nil

  /// Overrides the quota project for this download operation.
  ///
  /// By default, Google Cloud Storage attributes quota and billing usage to the project associated
  /// with the credentials, the project configured on `StorageClientOptions.client.quotaProject`,
  /// or the project owning the bucket. Setting `quotaProject` instructs the service to charge
  /// quota and billing for this download to the specified project ID or project number instead.
  ///
  /// This is commonly used when:
  /// - Downloading from a [Requester Pays] bucket where the caller's project must be billed for
  ///   data access and egress.
  /// - Authenticating with user credentials (such as those created by
  ///   `gcloud auth application-default login`), which are not inherently tied to a project.
  /// - Multiplexing downloads across multiple consumer projects using a single `StorageClient`.
  ///
  /// The authenticated principal must have the `serviceusage.services.use` IAM permission
  /// (granted by the [Service Usage Consumer] role, `roles/serviceusage.serviceUsageConsumer`) on
  /// the specified project.
  ///
  /// When set, the `x-goog-user-project` header is sent with this value, taking precedence over
  /// any client-level or credential-level quota project.
  ///
  /// [Requester Pays]: https://cloud.google.com/storage/docs/requester-pays
  /// [Service Usage Consumer]: https://cloud.google.com/service-usage/docs/access-control
  public var quotaProject: String? = nil

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

extension ReadObjectOptions {
  internal func withDefaults(_ defaults: Self) -> Self {
    var copy = self
    copy.resumePolicy = self.resumePolicy ?? defaults.resumePolicy
    copy.backoffPolicy = self.backoffPolicy ?? defaults.backoffPolicy
    copy.quotaProject = self.quotaProject ?? defaults.quotaProject
    return copy
  }

  internal var requestOptions: RequestOptions {
    RequestOptions().with { $0.quotaProject = self.quotaProject }
  }
}

/// Calculates the remaining range to request when resuming an interrupted download.
///
/// - Parameters:
///   - originalRange: The range requested in the original download operation.
///   - bytesReceived: The number of bytes successfully received and yielded so far.
///   - totalSize: The total size of the object if known from metadata or headers.
/// - Returns: The adjusted `ReadObjectRange` to request, or `nil` if all requested bytes have been received.
package func calculateResumeRange(
  originalRange: ReadObjectRange,
  bytesReceived: UInt64,
  totalSize: UInt64?
) -> ReadObjectRange? {
  guard Int64(exactly: bytesReceived) != nil else { return nil }
  switch originalRange.store {
  case .entire:
    return ReadObjectRange(fromOffset: bytesReceived)
  case .zero:
    return nil
  case .fromOffset(let offset):
    return ReadObjectRange(fromOffset: UInt64(offset) + bytesReceived)
  case .bounded(let range):
    return ReadObjectRange(
      start: UInt64(range.lowerBound) + bytesReceived,
      end: UInt64(range.upperBound)
    )
  case .suffix(let count):
    let count = UInt64(count)
    guard count > bytesReceived else { return nil }
    guard let totalSize else {
      return ReadObjectRange(suffix: count - bytesReceived)
    }
    guard totalSize > 0 else { return nil }
    let startOffset = totalSize > count ? (totalSize - count) : 0
    return ReadObjectRange(start: startOffset + bytesReceived, end: totalSize - 1)
  }
}
