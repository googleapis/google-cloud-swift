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

  /// Constructs a validated `https://<service>.<universeDomain><path>` URL.
  ///
  /// Rejects malformed universe domains or paths that inject ports, userinfo, extra host segments,
  /// queries, fragments, or invalid URL characters.
  ///
  /// - Throws: ``CredentialsError/parseError(_:)`` if a valid service URL cannot be constructed.
  func serviceURL(service: String, path: String) throws -> URL {
    let targetHost = "\(service).\(rawValue)"
    guard
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
  /// constructs `https://<service>.<universeDomain><defaultPath>` when `override` is `nil`.
  func resolveServiceURL(
    override: String?,
    service: String,
    defaultPath: String,
    settingName: String,
    requireNonRootPath: Bool = false,
    allowQuery: Bool = true,
    allowCustomHosts: Bool = true
  ) throws -> URL {
    if let override {
      return try validateServiceURL(
        override,
        service: service,
        settingName: settingName,
        requireNonRootPath: requireNonRootPath,
        allowQuery: allowQuery,
        allowCustomHosts: allowCustomHosts
      )
    }
    return try serviceURL(service: service, path: defaultPath)
  }

  /// Parses and validates an explicit `https` service endpoint URL against this universe domain.
  ///
  /// Enforces an `https` scheme, absence of userinfo and fragments, an unencoded non-empty host,
  /// optional path and query constraints, and universe domain host compatibility for `service`.
  func validateServiceURL(
    _ rawURL: String,
    service: String,
    settingName: String,
    requireNonRootPath: Bool = false,
    allowQuery: Bool = true,
    allowCustomHosts: Bool = true
  ) throws -> URL {
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
    try validateServiceEndpointHost(
      host,
      service: service,
      settingName: settingName,
      allowCustomHosts: allowCustomHosts
    )
    return canonicalURL
  }

  /// Validates that `host` does not target a conflicting Google Cloud universe domain for `service`.
  func validateServiceEndpointHost(
    _ host: String,
    service: String,
    settingName: String,
    allowCustomHosts: Bool = true
  ) throws {
    let bareHost =
      (host.hasPrefix("[") && host.hasSuffix("]") && host.count >= 2)
      ? String(host.dropFirst().dropLast()) : host
    if bareHost.lowercased() == "localhost" || bareHost == "127.0.0.1" || bareHost == "::1" {
      return
    }
    if bareHost.isEmpty
      || (!bareHost.contains(":")
        && host.split(separator: ".", omittingEmptySubsequences: false).contains(""))
    {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    let serviceLower = service.lowercased()
    let universeSuffix = ".\(rawValue)"

    if let firstDot = host.firstIndex(of: ".") {
      let firstLabelLower = host[..<firstDot].lowercased()
      let remainder = String(host[host.index(after: firstDot)...])

      if firstLabelLower == serviceLower {
        guard Self.matchesServiceRemainder(remainder, rawUniverse: rawValue, isDefault: isDefault)
        else {
          throw CredentialsError.parseError(
            "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
          )
        }
        return
      }

      let locationalSuffix = "-\(serviceLower)"
      if firstLabelLower.hasSuffix(locationalSuffix) {
        let prefixLabel = firstLabelLower.dropLast(locationalSuffix.count)
        let matchesLocational = remainder == rawValue
        let matchesPurposeRegional: Bool
        if remainder.hasSuffix(universeSuffix) {
          let regionPrefix = remainder.dropLast(universeSuffix.count)
          let parts = regionPrefix.split(separator: ".", omittingEmptySubsequences: false)
          matchesPurposeRegional =
            parts.count == 2 && !parts[0].isEmpty && parts[1].lowercased() == "rep"
        } else {
          matchesPurposeRegional = false
        }
        guard !prefixLabel.isEmpty, matchesLocational || matchesPurposeRegional else {
          throw CredentialsError.parseError(
            "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
          )
        }
        return
      }

      if firstLabelLower == "private" || firstLabelLower == "restricted" || firstLabelLower == "www"
      {
        guard remainder == rawValue else {
          throw CredentialsError.parseError(
            "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
          )
        }
        return
      }
    }

    let hostLower = host.lowercased()
    if !isDefault
      && (hostLower == Self.defaultRawValue
        || hostLower.hasSuffix(".\(Self.defaultRawValue)"))
    {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    if hostLower.contains(".p.") && !host.hasSuffix(universeSuffix) {
      throw CredentialsError.parseError(
        "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
      )
    }

    if !allowCustomHosts {
      guard host.hasSuffix(universeSuffix), host.count > universeSuffix.count else {
        throw CredentialsError.parseError(
          "The \(settingName) host (\(host)) does not match universe_domain (\(rawValue))."
        )
      }
    }
  }

  private static func matchesServiceRemainder(
    _ remainder: String,
    rawUniverse: String,
    isDefault: Bool
  ) -> Bool {
    if remainder == rawUniverse {
      return true
    }
    let universeSuffix = ".\(rawUniverse)"
    guard remainder.hasSuffix(universeSuffix) else {
      return false
    }
    let regionPrefix = remainder.dropLast(universeSuffix.count)
    let parts = regionPrefix.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 2 && !parts[0].isEmpty && parts[1].lowercased() == "rep" {
      return true
    }
    if isDefault && parts.count == 1 && !parts[0].isEmpty {
      return true
    }
    return false
  }

  public var description: String {
    rawValue
  }

  public var debugDescription: String {
    "_UniverseDomain(\(String(reflecting: rawValue)))"
  }
}
