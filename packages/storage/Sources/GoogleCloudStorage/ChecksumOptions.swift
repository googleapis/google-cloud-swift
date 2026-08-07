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

/// Strategy for data integrity validation.
public enum ChecksumValidation: Sendable {
  /// Do not perform client-side checksum validation.
  case none

  /// Automatically calculate and validate CRC32C (recommended).
  case crc32c

  /// Automatically calculate and validate MD5.
  case md5
}

/// Configuration options for checksum validation.
public struct ChecksumOptions: Sendable, Hashable {
  /// Checksum mode / value for CRC32C.
  public var crc32c: ChecksumValue?

  /// Checksum mode / value for MD5.
  public var md5: ChecksumValue?

  /// Specifies how a checksum should be provided for validation.
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
      let bigEndian = intValue.bigEndian
      let base64 = withUnsafeBytes(of: bigEndian) { Data($0).base64EncodedString() }
      self = .value(base64)
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
