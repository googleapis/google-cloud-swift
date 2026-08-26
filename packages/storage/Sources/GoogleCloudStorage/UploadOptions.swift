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

import Crypto
import Foundation
import GoogleCloudGax
import GoogleCloudWKT

/// Errors thrown when validating or creating a `CustomerEncryptionKeyOptions`.
public enum CustomerEncryptionKeyError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// The key length in bytes does not match the expected length required by the algorithm.
  case invalidKeyLength(actual: Int, expected: Int)

  /// The provided key string is not a valid Base64-encoded string.
  case invalidBase64Key

  public var description: String {
    switch self {
    case .invalidKeyLength(let actual, let expected):
      return
        "Invalid customer encryption key length: got \(actual) bytes, expected \(expected) bytes."
    case .invalidBase64Key:
      return "Customer encryption key is not a valid base64-encoded string."
    }
  }
}

/// Options for [Customer-Supplied Encryption Keys] (CSEK).
///
/// As an additional layer on top of [standard Cloud Storage encryption], you can choose to provide
/// your own AES-256 encryption key, encoded in [standard Base64]. This key is known as a
/// customer-supplied encryption key. If you provide a customer-supplied encryption key,
/// Cloud Storage does not permanently store your key in its servers or otherwise manage your key.
///
/// Encryption algorithm used for Customer-Supplied Encryption Keys (CSEK).
public enum CustomerEncryptionAlgorithm: String, Sendable, Equatable, CustomStringConvertible {
  /// AES-256 encryption algorithm (default and currently the only supported algorithm in Cloud Storage).
  case aes256 = "AES256"

  public var description: String {
    rawValue
  }
}

/// Options for [Customer-Supplied Encryption Keys] (CSEK).
///
/// As an additional layer on top of [standard Cloud Storage encryption], you can choose to provide
/// your own AES-256 encryption key, encoded in [standard Base64]. This key is known as a
/// customer-supplied encryption key. If you provide a customer-supplied encryption key,
/// Cloud Storage does not permanently store your key in its servers or otherwise manage your key.
///
/// [standard Cloud Storage encryption]: https://docs.cloud.google.com/storage/docs/encryption/default-keys
/// [standard Base64]: https://datatracker.ietf.org/doc/html/rfc4648#section-4
/// [Customer-Supplied Encryption Keys]: https://docs.cloud.google.com/storage/docs/encryption/customer-supplied-keys
public struct CustomerEncryptionKeyOptions: Sendable, Equatable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The encryption algorithm used (e.g. `.aes256`).
  public let algorithm: CustomerEncryptionAlgorithm

  /// The raw symmetric key material.
  public let key: SymmetricKey

  public static func == (lhs: CustomerEncryptionKeyOptions, rhs: CustomerEncryptionKeyOptions)
    -> Bool
  {
    lhs.algorithm == rhs.algorithm && lhs.key == rhs.key
  }

  /// The Base64-encoded string representation of the encryption key.
  public var keyBase64: String {
    key.withUnsafeBytes { Data($0).base64EncodedString() }
  }

  /// The Base64-encoded SHA-256 digest of the key material used for header validation.
  public var keyHashBase64: String {
    let data = key.withUnsafeBytes { Data($0) }
    let hash = SHA256.hash(data: data)
    return Data(hash).base64EncodedString()
  }

  public var description: String {
    "CustomerEncryptionKeyOptions(algorithm: \(algorithm.rawValue), keyHashBase64: \(keyHashBase64))"
  }

  public var debugDescription: String {
    description
  }

  /// Creates a `CustomerEncryptionKeyOptions` from a `SymmetricKey`.
  ///
  /// For the default `.aes256` algorithm, the key must be exactly 32 bytes (256 bits).
  public init(key: SymmetricKey, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    let count = key.withUnsafeBytes { $0.count }
    if algorithm == .aes256 && count != 32 {
      throw CustomerEncryptionKeyError.invalidKeyLength(actual: count, expected: 32)
    }
    self.algorithm = algorithm
    self.key = key
  }

  /// Creates a `CustomerEncryptionKeyOptions` from Apple CryptoKit / Swift Crypto `SymmetricKey`.
  public init(symmetricKey: SymmetricKey, algorithm: CustomerEncryptionAlgorithm = .aes256)
    throws
  {
    try self.init(key: symmetricKey, algorithm: algorithm)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from pre-computed values.
  public init(
    algorithm: CustomerEncryptionAlgorithm = .aes256, keyBase64: String, keyHashBase64: String
  ) {
    let keyData = Data(base64Encoded: keyBase64) ?? Data(keyBase64.utf8)
    self.algorithm = algorithm
    self.key = SymmetricKey(data: keyData)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from raw key bytes (`Data`).
  ///
  /// For the default `.aes256` algorithm, the key must be exactly 32 bytes (256 bits).
  /// The key and its SHA-256 hash are automatically Base64-encoded.
  public init(key: Data, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    if algorithm == .aes256 && key.count != 32 {
      throw CustomerEncryptionKeyError.invalidKeyLength(actual: key.count, expected: 32)
    }
    self.algorithm = algorithm
    self.key = SymmetricKey(data: key)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from raw key bytes (`[UInt8]`).
  public init(keyBytes: [UInt8], algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    try self.init(key: Data(keyBytes), algorithm: algorithm)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from a Base64-encoded key string.
  ///
  /// For the default `.aes256` algorithm, the decoded key must be exactly 32 bytes (256 bits).
  /// The SHA-256 hash is automatically computed and Base64-encoded.
  public init(keyBase64: String, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    guard let keyData = Data(base64Encoded: keyBase64) else {
      throw CustomerEncryptionKeyError.invalidBase64Key
    }
    try self.init(key: keyData, algorithm: algorithm)
  }
}

/// Preconditions for GCS operations.
public struct StoragePreconditions: Sendable {
  /// Makes the operation succeed only if the object's current generation matches this value.
  public var ifGenerationMatch: Int64?

  /// Makes the operation succeed only if the object's current generation does not match this value.
  public var ifGenerationNotMatch: Int64?

  /// Makes the operation succeed only if the object's current metageneration matches this value.
  public var ifMetagenerationMatch: Int64?

  /// Makes the operation succeed only if the object's current metageneration does not match this value.
  public var ifMetagenerationNotMatch: Int64?

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

extension StoragePreconditions {
  /// Converts non-nil precondition fields into URL query items.
  package var queryItems: [URLQueryItem] {
    var items: [URLQueryItem] = []
    if let ifGenerationMatch {
      items.append(URLQueryItem(name: "ifGenerationMatch", value: String(ifGenerationMatch)))
    }
    if let ifGenerationNotMatch {
      items.append(URLQueryItem(name: "ifGenerationNotMatch", value: String(ifGenerationNotMatch)))
    }
    if let ifMetagenerationMatch {
      items.append(
        URLQueryItem(name: "ifMetagenerationMatch", value: String(ifMetagenerationMatch)))
    }
    if let ifMetagenerationNotMatch {
      items.append(
        URLQueryItem(name: "ifMetagenerationNotMatch", value: String(ifMetagenerationNotMatch)))
    }
    return items
  }
}

/// Predefined ACL options for object uploads.
public enum PredefinedAcl: String, Sendable, Equatable {
  case authenticatedRead
  case bucketOwnerFullControl
  case bucketOwnerRead
  case `private`
  case projectPrivate
  case publicRead
}

/// Object retention policy configuration for a GCS Object.
public struct ObjectRetention: Sendable, Codable, Equatable {
  public var mode: String?
  public var retainUntilTime: GoogleCloudWKT.Timestamp?

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Owner metadata for a GCS Object.
public struct ObjectOwner: Sendable, Codable, Equatable {
  public var entity: String?
  public var entityId: String?

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Payload for a custom context entry on a Cloud Storage object.
extension ObjectCustomContextPayload: ExpressibleByStringLiteral {
  public init(
    value: String? = nil,
    createTime: GoogleCloudWKT.Timestamp? = nil,
    updateTime: GoogleCloudWKT.Timestamp? = nil
  ) {
    self.init()
    if let value = value { self.value = value }
    self.createTime = createTime
    self.updateTime = updateTime
  }

  public init(stringLiteral value: String) {
    self.init(value: value)
  }
}

/// Container for object contexts on a Cloud Storage object.
extension ObjectContexts: ExpressibleByDictionaryLiteral {
  public init(custom: [String: ObjectCustomContextPayload] = [:]) {
    self.init()
    self.custom = custom
  }

  public init(customValues: [String: String]) {
    self.init()
    self.custom = customValues.mapValues { val in ObjectCustomContextPayload(value: val) }
  }

  public init(dictionaryLiteral elements: (String, ObjectCustomContextPayload)...) {
    self.init(custom: Dictionary(uniqueKeysWithValues: elements))
  }
}

/// Represents the metadata of the object to be created.
public struct UploadMetadata: Sendable, Codable, Equatable {
  /// Content-Type header of the object data (e.g. "application/json", "image/png").
  public var contentType: String?

  /// Content-Encoding header of the object data (e.g. "gzip").
  public var contentEncoding: String?

  /// Content-Disposition header of the object data (e.g. "inline", "attachment; filename=filename.ext").
  public var contentDisposition: String?

  /// Content-Language header of the object data (e.g. "en", "es").
  public var contentLanguage: String?

  /// Cache-Control header of the object data (e.g. "public, max-age=3600").
  public var cacheControl: String?

  /// Custom key-value metadata pairs associated with the object.
  public var customMetadata: [String: String]?

  /// Storage class of the object (e.g., "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE").
  public var storageClass: String?

  /// Custom time set by user for the object.
  public var customTime: GoogleCloudWKT.Timestamp?

  /// Event-based hold status for the object.
  public var eventBasedHold: Bool?

  /// Temporary hold status for the object.
  public var temporaryHold: Bool?

  /// Access Control List (ACL) entries for the object.
  public var acl: [ObjectAccessControl]?

  /// Object retention configuration.
  public var retention: ObjectRetention?

  /// Owner information for the object.
  public var owner: ObjectOwner?

  /// Object contexts associated with the object.
  public var contexts: ObjectContexts?

  enum CodingKeys: String, CodingKey {
    case contentType
    case contentEncoding
    case contentDisposition
    case contentLanguage
    case cacheControl
    case customMetadata = "metadata"
    case storageClass
    case customTime
    case eventBasedHold
    case temporaryHold
    case acl
    case retention
    case owner
    case contexts
  }

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Configuration options for object upload operations in Google Cloud Storage.
///
/// Use `UploadOptions` to customize upload behaviors when calling `StorageClient.upload(...)`.
/// Options include setting chunk size for resumable uploads, object metadata, preconditions (such as generation matches),
/// encryption settings (CMEK and CSEK), checksum validation strategies, and access control presets (Predefined ACLs).
///
/// ## Configuration Styles
///
/// Configure `UploadOptions` by using the `.with` closure builder.
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.chunkSize = 16 * 1024 * 1024  // 16 MiB
///   $0.predefinedAcl = .publicRead
///   $0.metadata = UploadMetadata().with { meta in
///     meta.contentType = "application/json"
///     meta.customMetadata = ["env": "prod"]
///   }
/// }
/// ```
///
/// ## Key Configuration Features
///
/// ### Object Metadata
///
/// Attach fixed key metadata (such as `Content-Type` or `Cache-Control`) and custom key-value pairs to the uploaded object:
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.metadata = UploadMetadata().with { meta in
///     meta.contentType = "image/png"
///     meta.cacheControl = "public, max-age=3600"
///     meta.customMetadata = ["author": "Jane Doe", "department": "Engineering"]
///   }
/// }
/// ```
///
/// ### Object Contexts
///
/// Attach object contexts to improve how you categorize, track, and search your data:
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.metadata = UploadMetadata().with { meta in
///     meta.contexts = ObjectContexts(custom: [
///       "environment": ObjectCustomContextPayload(value: "production"),
///       "team": "Engineering"
///     ])
///   }
/// }
/// ```
///
/// ### Preconditions
///
/// Apply preconditions to the upload. For example, guaranteeing an object is only created if it does not already exist:
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.preconditions = StoragePreconditions().with {
///     $0.ifGenerationMatch = 0  // Succeeds only if the object does not exist
///   }
/// }
/// ```
///
/// ### Checksum Validation
///
/// Configure client-side data integrity verification (CRC32C and/or MD5):
///
/// ```swift
/// // Use automatic CRC32C calculation (default)
/// let options = UploadOptions().with {
///   $0.checksums = .default
/// }
///
/// // Pass a pre-computed CRC32C checksum
/// let options = UploadOptions().with {
///   $0.checksums = ChecksumOptions(crc32c: "AAAAAA==")
/// }
/// ```
///
/// ### Encryption (CMEK / CSEK)
///
/// Protect uploaded objects with Customer-Managed Encryption Keys (CMEK) or Customer-Supplied Encryption Keys (CSEK):
///
/// ```swift
/// // Customer-Managed Encryption Key (CMEK) via Cloud KMS
/// let options = UploadOptions().with {
///   $0.kmsKeyName = "projects/my-project/locations/global/keyRings/my-ring/cryptoKeys/my-key"
/// }
///
/// // Customer-Supplied Encryption Key (CSEK)
/// let csek = try CustomerEncryptionKeyOptions(keyBase64: "your-base64-encoded-256bit-key==")
/// let options = UploadOptions().with {
///   $0.customerEncryptionKey = csek
/// }
/// ```
///
/// ### Predefined Access Control Lists (ACLs)
///
/// Set predefined permissions for the object upon upload:
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.predefinedAcl = .publicRead
/// }
/// ```
///
/// ## Uploading with Options
///
/// Pass your configured options to `StorageClient.upload(...)`:
///
/// ```swift
/// let options = UploadOptions().with {
///   $0.chunkSize = 16 * 1024 * 1024
///   $0.metadata = UploadMetadata().with {
///     $0.contentType = "text/csv"
///   }
/// }
///
/// let task = storageClient.upload(
///   fileURL,
///   to: "my-bucket",
///   as: "data/report.csv",
///   options: options
/// )
/// ```
public struct UploadOptions: Sendable {
  /// The default chunk size in bytes (8 MB) for resumable uploads.
  public static let defaultChunkSize: Int = 8 * 1024 * 1024

  /// The default threshold in bytes (8 MB) between simple and resumable uploads.
  public static let defaultResumableUploadThreshold: Int = 8 * 1024 * 1024

  /// The chunk size in bytes for resumable uploads. Defaults to `defaultChunkSize` (8 MB).
  public var chunkSize: Int = defaultChunkSize

  /// The threshold in bytes between simple and resumable uploads.
  ///
  /// Uploads of known size strictly less than this threshold use simple (multipart) upload;
  /// uploads greater than or equal to this threshold (or of unknown size) use resumable upload.
  /// When `nil`, the upload operation falls back to `StorageClientOptions.upload.resumableUploadThreshold`
  /// or the default threshold (`defaultResumableUploadThreshold`, 8 MB).
  public var resumableUploadThreshold: Int?

  /// Preconditions (e.g. `ifGenerationMatch`) for the upload operation.
  public var preconditions: StoragePreconditions?

  /// Resource name of the Cloud KMS key used to encrypt the object (Customer-Managed Encryption Keys / CMEK).
  public var kmsKeyName: String?

  /// Options for Customer-Supplied Encryption Keys (CSEK).
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?

  /// Configuration options for upload checksum validation.
  public var checksums: ChecksumOptions = .default

  /// Metadata associated with the object to be created.
  public var metadata: UploadMetadata?

  /// Predefined ACL to apply to the uploaded object (e.g. `.publicRead`, `.private`).
  public var predefinedAcl: PredefinedAcl?

  /// Overrides the resume policy for this upload.
  public var resumePolicy: (any ResumePolicy<UploadDetails>)? = nil

  /// Overrides the backoff policy for this upload.
  public var backoffPolicy: (any BackoffPolicy)? = nil

  /// Legacy validation enum property for backward compatibility.
  public var validation: ChecksumValidation {
    get {
      if checksums.crc32c == .auto && checksums.md5 == nil {
        return .crc32c
      } else if checksums.md5 == .auto && checksums.crc32c == nil {
        return .md5
      } else {
        return .none
      }
    }
    set {
      switch newValue {
      case .none:
        checksums = .none
      case .crc32c:
        checksums = ChecksumOptions(crc32c: .auto, md5: nil)
      case .md5:
        checksums = ChecksumOptions(crc32c: nil, md5: .auto)
      }
    }
  }

  public static var `default`: UploadOptions { UploadOptions() }

  public init() {}

  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}

/// Customer encryption metadata returned in object responses.
extension CustomerEncryption {
  /// Base64-encoded string representation of `keySha256Bytes`.
  public var keySha256: String? {
    get {
      guard !keySha256Bytes.isEmpty else { return nil }
      return keySha256Bytes.base64EncodedString()
    }
    set {
      keySha256Bytes = newValue.flatMap { Data(base64Encoded: $0) } ?? Data()
    }
  }

  private enum ExtensionCodingKeys: String, CodingKey {
    case encryptionAlgorithm
    case keySha256Bytes
    case keySha256
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: ExtensionCodingKeys.self)
    self.encryptionAlgorithm =
      try container.decodeIfPresent(String.self, forKey: .encryptionAlgorithm) ?? ""
    if let data = try container.decodeIfPresent(Data.self, forKey: .keySha256Bytes) {
      self.keySha256Bytes = data
    } else if let b64 = try container.decodeIfPresent(String.self, forKey: .keySha256),
      let data = Data(base64Encoded: b64)
    {
      self.keySha256Bytes = data
    } else {
      self.keySha256Bytes = Data()
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: ExtensionCodingKeys.self)
    try container.encode(encryptionAlgorithm, forKey: .encryptionAlgorithm)
    try container.encode(keySha256Bytes, forKey: .keySha256Bytes)
    if !keySha256Bytes.isEmpty {
      try container.encode(keySha256Bytes.base64EncodedString(), forKey: .keySha256)
    }
  }
}

/// Represents a parsed HTTP `Range` header (e.g. `bytes=0-1999`).
struct HttpRange: Sendable, Hashable, Equatable {
  let start: UInt64?
  let end: UInt64?

  init(start: UInt64? = nil, end: UInt64? = nil) {
    self.start = start
    self.end = end
  }

  /// Parses an HTTP `Range` header and returns the next byte offset (`end + 1`).
  static func parseNextRangeStart(_ header: String) throws -> UInt64 {
    let range = try parse(header)
    guard let end = range.end else {
      throw UploadError.invalidRangeHeader(header)
    }
    return end + 1
  }

  /// Parses an HTTP `Range` header value (e.g., `"bytes=0-1999"`).
  static func parse(_ header: String) throws -> HttpRange {
    let trimmed = header.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("bytes=") else {
      throw UploadError.invalidRangeHeader(header)
    }
    let rangeStr = trimmed.dropFirst("bytes=".count).trimmingCharacters(in: .whitespaces)
    let parts = rangeStr.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      throw UploadError.invalidRangeHeader(header)
    }

    let startStr = parts[0]
    let endStr = parts[1]

    let start = startStr.isEmpty ? nil : UInt64(startStr)
    let end = endStr.isEmpty ? nil : UInt64(endStr)

    if startStr.isEmpty && endStr.isEmpty {
      throw UploadError.invalidRangeHeader(header)
    }
    if !startStr.isEmpty && start == nil {
      throw UploadError.invalidRangeHeader(header)
    }
    if !endStr.isEmpty && end == nil {
      throw UploadError.invalidRangeHeader(header)
    }
    if start == nil && end == nil {
      throw UploadError.invalidRangeHeader(header)
    }
    if let s = start, let e = end, s > e {
      throw UploadError.invalidRangeHeader(header)
    }

    return HttpRange(start: start, end: end)
  }
}
