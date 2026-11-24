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

public import Foundation

/// Represents a normalized Google Cloud universe domain (such as `"googleapis.com"`).
///
/// A universe is an isolated Google Cloud environment, such as the standard universe
/// (`googleapis.com`) or a sovereign, air-gapped, or partner deployment.
///
/// Empty strings (`""`) and `nil` configuration values normalize to `nil` via
/// ``init(nonEmpty:)`` or fall back to ``default`` via ``resolve(_:)``. Non-empty values are
/// preserved verbatim for exact case-sensitive comparison per AIP-4110 and validated when
/// constructing endpoint URLs.
@_spi(GoogleCloudInternal)
public struct _UniverseDomain: Sendable, Hashable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The default Google Cloud universe domain string (`"googleapis.com"`).
  public static let defaultRawValue = "googleapis.com"

  /// The environment variable name inspected by client transports (`"GOOGLE_CLOUD_UNIVERSE_DOMAIN"`).
  public static let environmentVariable = "GOOGLE_CLOUD_UNIVERSE_DOMAIN"

  /// The default Google Cloud universe domain (`"googleapis.com"`).
  public static let `default` = _UniverseDomain(unchecked: defaultRawValue)

  /// The non-empty universe domain string.
  public let rawValue: String

  /// Whether this universe domain equals the standard Google Cloud universe (`"googleapis.com"`).
  public var isDefault: Bool {
    rawValue == Self.defaultRawValue
  }

  private init(unchecked rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a universe domain when `rawValue` is non-nil and non-empty, or returns `nil`
  /// when `rawValue` is `nil` or `""`.
  public init?(nonEmpty rawValue: String?) {
    guard let rawValue, !rawValue.isEmpty else {
      return nil
    }
    self.rawValue = rawValue
  }

  /// Resolves the first non-empty candidate universe domain, falling back to ``default``
  /// (`"googleapis.com"`).
  public static func resolve(_ candidates: String?...) -> _UniverseDomain {
    for candidate in candidates {
      if let resolved = _UniverseDomain(nonEmpty: candidate) {
        return resolved
      }
    }
    return .default
  }

  /// Resolves a client's effective universe domain from an explicit configuration option or
  /// `GOOGLE_CLOUD_UNIVERSE_DOMAIN` in `ProcessInfo.processInfo.environment`.
  public static func resolve(configured: String?) -> _UniverseDomain {
    resolve(configured: configured, environment: ProcessInfo.processInfo.environment)
  }

  /// Resolves a client's effective universe domain in precedence order:
  /// 1. `configured` (when non-empty)
  /// 2. `environment["GOOGLE_CLOUD_UNIVERSE_DOMAIN"]` (when non-empty)
  /// 3. ``default`` (`"googleapis.com"`)
  public static func resolve(
    configured: String?,
    environment: [String: String]
  ) -> _UniverseDomain {
    resolve(configured, environment[environmentVariable])
  }

  /// Constructs a validated `https://<service>.<universeDomain><path>` URL.
  ///
  /// Rejects malformed universe domains that inject ports, userinfo, extra path segments,
  /// queries, fragments, or invalid URL characters.
  ///
  /// - Throws: ``CredentialsError/parseError(_:)`` if a valid service URL cannot be constructed.
  public func serviceURL(service: String, path: String) throws -> URL {
    let targetHost = "\(service).\(rawValue)"
    let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
    let urlString = "https://\(targetHost)\(normalizedPath)"
    guard
      let parsed = URLComponents(string: urlString, encodingInvalidCharacters: false),
      parsed.scheme == "https",
      parsed.host == targetHost,
      parsed.percentEncodedHost == targetHost,
      parsed.port == nil,
      parsed.user == nil,
      parsed.password == nil,
      parsed.percentEncodedPath == normalizedPath,
      parsed.query == nil,
      parsed.fragment == nil,
      let resolvedURL = parsed.url
    else {
      throw CredentialsError.parseError(
        "Invalid universe_domain for \(service) endpoint: '\(rawValue)'"
      )
    }
    return resolvedURL
  }

  public var description: String {
    rawValue
  }

  public var debugDescription: String {
    "_UniverseDomain(\(String(reflecting: rawValue)))"
  }
}
