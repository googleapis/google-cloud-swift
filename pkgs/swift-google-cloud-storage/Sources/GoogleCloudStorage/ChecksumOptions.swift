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

/// Configuration options for checksum validation.
public struct ChecksumOptions: Sendable, Hashable {
  /// Checksum mode / value for CRC32C.
  public var crc32c: ChecksumValue?

  /// Checksum mode / value for MD5.
  public var md5: ChecksumValue?

  /// Specifies how a checksum should be provided for validation.
  ///
  /// - Note: As Google Cloud APIs and client libraries evolve, new cases may be added to this
  ///   enumeration in minor or patch releases. Always handle unexpected cases using an `@unknown default:`
  ///   clause in `switch` statements.
  public enum ChecksumValue: Sendable, Hashable, ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral
  {
    /// Automatically calculate the checksum on-the-fly during streaming operations.
    case auto

    /// Use a pre-computed checksum value (e.g., Base64 encoded string).
    case value(String)

    /// Creates a `ChecksumValue` from a string literal containing a pre-computed checksum.
    public init(stringLiteral value: String) {
      self = .value(value)
    }

    /// Creates a `ChecksumValue` from a 32-bit unsigned integer CRC32C checksum value.
    public init(_ intValue: UInt32) {
      self = .value(crc32cBase64(intValue))
    }

    /// Creates a `ChecksumValue` from an integer literal containing a CRC32C checksum value.
    public init(integerLiteral value: UInt64) {
      self.init(UInt32(truncatingIfNeeded: value))
    }
  }

  /// Creates a new `ChecksumOptions` configuration for validating data with Google Cloud Storage.
  ///
  /// You can configure:
  /// - `.auto`: automatic on-the-fly calculation,
  /// - `.value("...")` or a string literal `"..."`: pre-computed values
  ///
  /// You can also enable both crc32c and md5  checksums simultaneously.
  public init(crc32c: ChecksumValue? = .auto, md5: ChecksumValue? = nil) {
    self.crc32c = crc32c
    self.md5 = md5
  }

  /// Default options: Automatically calculate CRC32C on-the-fly.
  public static var `default`: ChecksumOptions {
    ChecksumOptions(crc32c: .auto, md5: nil)
  }

  /// No checksum validation.
  public static var none: ChecksumOptions {
    ChecksumOptions(crc32c: nil, md5: nil)
  }
}

/// Encodes a 32-bit CRC32C checksum as a Base64 string of its 4 big-endian bytes, matching the
/// representation used by Google Cloud Storage in `x-goog-hash` headers and object metadata.
///
/// This helper constructs the 4-byte array via bitwise shifts rather than `withUnsafeBytes(of:)`
/// to avoid raw pointer operations under `-strict-memory-safety` (SE-0458) and to remain
/// compatible across Swift 6.2/6.3 (where `withUnsafeBytes(of:)` is `@unsafe`) and Swift 6.4+
/// (where `withUnsafeBytes(of:)` is `@safe` and rejects `unsafe` with `[#UnnecessaryUnsafe]`).
func crc32cBase64(_ value: UInt32) -> String {
  Data([
    UInt8((value >> 24) & 0xFF),
    UInt8((value >> 16) & 0xFF),
    UInt8((value >> 8) & 0xFF),
    UInt8(value & 0xFF),
  ]).base64EncodedString()
}
