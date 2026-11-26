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

  /// Whether `rawValue` consists solely of non-empty RFC 1035 / RFC 1123 ASCII LDH domain labels
  /// (`[A-Za-z0-9-]`, not starting or ending with `-`), blocking URL delimiters, RFC 3986
  /// `sub-delims` (such as `,` or `;`), trailing dots, whitespace, and non-ASCII characters.
  public var isValidSyntax: Bool {
    let labels = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard !labels.isEmpty else {
      return false
    }
    return labels.allSatisfy { label in
      !label.isEmpty
        && label.utf8.count <= 63
        && !label.hasPrefix("-")
        && !label.hasSuffix("-")
        && label.utf8.allSatisfy { byte in
          (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || byte == 0x2D
        }
    }
  }

  /// Constructs a validated `https://<service>.<universeDomain><path>` URL.
  ///
  /// Rejects malformed universe domains or paths that inject ports, userinfo, extra host segments,
  /// queries, fragments, or invalid URL characters.
  ///
  /// - Throws: ``CredentialsError/parseError(_:)`` if a valid service URL cannot be constructed.
  func serviceURL(service: String, path: String) throws -> URL {
    let targetHost = "\(service).\(rawValue)"
    guard
      isValidSyntax,
      let origin = URLComponents(string: "https://\(targetHost)", encodingInvalidCharacters: false),
      origin.scheme == "https",
      origin.host == targetHost,
      origin.percentEncodedHost == targetHost,
      origin.port == nil,
      origin.user == nil,
      origin.password == nil,
      origin.percentEncodedPath.isEmpty,
      origin.percentEncodedQuery == nil,
      origin.percentEncodedFragment == nil
    else {
      throw CredentialsError.parseError(
        "Invalid universe_domain for \(service) endpoint: '\(rawValue)'"
      )
    }

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
      parsed.percentEncodedQuery == nil,
      parsed.percentEncodedFragment == nil,
      let resolvedURL = parsed.url
    else {
      throw CredentialsError.parseError(
        "Invalid path for \(service) endpoint: '\(path)'"
      )
    }
    return resolvedURL
  }

  /// Resolves an optional `https` service endpoint URL override against this universe domain, or
  /// constructs `https://<service>.<universeDomain><defaultPath>` when `override` is `nil`,
  /// returning any required `Host` header override for shared multi-service / PSC gateways.
  func resolveServiceEndpoint(
    override: String?,
    service: String,
    defaultPath: String,
    settingName: String,
    requireNonRootPath: Bool = false,
    allowQuery: Bool = true,
    allowCustomHosts: Bool = true
  ) throws -> (url: URL, hostHeader: String?) {
    if let override {
      return try validateServiceEndpoint(
        override,
        service: service,
        settingName: settingName,
        requireNonRootPath: requireNonRootPath,
        allowQuery: allowQuery,
        allowCustomHosts: allowCustomHosts
      )
    }
    return (url: try serviceURL(service: service, path: defaultPath), hostHeader: nil)
  }

  /// Parses and validates an explicit `https` service endpoint URL against this universe domain,
  /// returning both the canonical URL and any `Host` header override required for shared gateways.
  func validateServiceEndpoint(
    _ rawURL: String,
    service: String,
    settingName: String,
    requireNonRootPath: Bool = false,
    allowQuery: Bool = true,
    allowCustomHosts: Bool = true
  ) throws -> (url: URL, hostHeader: String?) {
    guard isDefault || isValidSyntax else {
      throw CredentialsError.parseError(
        "Invalid universe_domain for \(service) endpoint: '\(rawValue)'"
      )
    }
    guard
      !rawURL.isEmpty,
      let parsed = URLComponents(string: rawURL, encodingInvalidCharacters: false),
      parsed.scheme?.lowercased() == "https",
      parsed.user == nil,
      parsed.password == nil,
      allowQuery || parsed.percentEncodedQuery == nil,
      parsed.percentEncodedFragment == nil,
      let percentEncodedHost = parsed.percentEncodedHost,
      !percentEncodedHost.isEmpty,
      !percentEncodedHost.contains("%"),
      let host = parsed.host,
      !host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).isEmpty,
      !requireNonRootPath
        || (!parsed.percentEncodedPath.isEmpty && parsed.percentEncodedPath != "/"),
      let canonicalURL = parsed.url
    else {
      throw CredentialsError.parseError("Invalid \(settingName): '\(rawURL)'")
    }
    let hostHeader = try validateServiceEndpointHost(
      host,
      service: service,
      settingName: settingName,
      allowCustomHosts: allowCustomHosts
    )
    return (url: canonicalURL, hostHeader: hostHeader)
  }

  /// Validates that `host` does not target a conflicting Google Cloud universe domain for `service`,
  /// returning `<service>.<universeDomain>` when `host` is a shared gateway requiring a `Host` override.
  @discardableResult
  func validateServiceEndpointHost(
    _ host: String,
    service: String,
    settingName: String,
    allowCustomHosts: Bool = true
  ) throws -> String? {
    let bareHost =
      (host.hasPrefix("[") && host.hasSuffix("]") && host.count >= 2)
      ? String(host.dropFirst().dropLast()) : host
    let bareHostASCII = Self.asciiLowercased(bareHost)
    if bareHostASCII == "localhost" || bareHost == "127.0.0.1" || bareHost == "::1" {
      return nil
    }
    if bareHost.isEmpty
      || (!bareHost.contains(":")
        && host.split(separator: ".", omittingEmptySubsequences: false).contains(""))
    {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    let hostASCII = Self.asciiLowercased(host)
    let serviceLower = Self.asciiLowercased(service)
    let universeSuffix = ".\(rawValue)"

    // `hostASCII.hasSuffix(universeSuffix)` matches RFC 3986 uppercase URL hostnames against
    // canonical lowercase universe domains, while `host.hasSuffix(universeSuffix)` preserves
    // exact case-sensitive suffix matching when `rawValue` itself contains uppercase ASCII.
    if host.hasSuffix(universeSuffix) || hostASCII.hasSuffix(universeSuffix) {
      let prefixLower = String(hostASCII.dropLast(universeSuffix.count))
      guard
        !prefixLower.isEmpty,
        Self.isValidServiceOrGatewayPrefix(
          prefixLower,
          serviceLower: serviceLower,
          isDefaultUniverse: isDefault,
          allowServiceHyphenPrefix: allowCustomHosts
        )
      else {
        throw CredentialsError.parseError(
          "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
        )
      }
      if Self.isSharedGatewayPrefix(prefixLower) {
        return "\(serviceLower).\(rawValue)"
      }
      return nil
    }

    guard allowCustomHosts else {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    if !isDefault
      && (hostASCII == Self.defaultRawValue
        || hostASCII.hasSuffix(".\(Self.defaultRawValue)"))
    {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    if hostASCII.contains(".p.") || hostASCII.contains(".rep.") {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    if let firstDot = hostASCII.firstIndex(of: ".") {
      let firstLabel = hostASCII[..<firstDot]
      if firstLabel == serviceLower
        || firstLabel.hasSuffix("-\(serviceLower)")
        || firstLabel == "private"
        || firstLabel == "restricted"
        || firstLabel == "www"
      {
        throw CredentialsError.parseError(
          "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
        )
      }
    }
    return nil
  }

  private static func isSharedGatewayPrefix(_ prefixLower: String) -> Bool {
    prefixLower == "private"
      || prefixLower == "restricted"
      || prefixLower == "www"
      || (prefixLower.hasSuffix(".p") && prefixLower.count > 2)
  }

  private static func isValidServiceOrGatewayPrefix(
    _ prefixLower: String,
    serviceLower: String,
    isDefaultUniverse: Bool,
    allowServiceHyphenPrefix: Bool
  ) -> Bool {
    if prefixLower == serviceLower || isSharedGatewayPrefix(prefixLower) {
      return true
    }
    if !prefixLower.contains(".") {
      if prefixLower.hasSuffix("-\(serviceLower)") && prefixLower.count > serviceLower.count + 1 {
        return true
      }
      if allowServiceHyphenPrefix
        && prefixLower.hasPrefix("\(serviceLower)-")
        && prefixLower.count > serviceLower.count + 1
      {
        return true
      }
      return false
    }
    let parts = prefixLower.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 3 && parts[2] == "rep" && !parts[1].isEmpty {
      return parts[0] == serviceLower
        || (parts[0].hasSuffix("-\(serviceLower)") && parts[0].count > serviceLower.count + 1)
    }
    if isDefaultUniverse && parts.count == 2 && parts[0] == serviceLower && !parts[1].isEmpty {
      return true
    }
    return false
  }

  private static func asciiLowercased(_ string: String) -> String {
    String(
      decoding: string.utf8.map { byte in
        (byte >= 0x41 && byte <= 0x5A) ? byte + 32 : byte
      },
      as: UTF8.self
    )
  }

  public var description: String {
    rawValue
  }

  public var debugDescription: String {
    "_UniverseDomain(\(String(reflecting: rawValue)))"
  }
}
