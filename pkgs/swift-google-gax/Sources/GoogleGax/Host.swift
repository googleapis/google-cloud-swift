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

/// Helper to calculate the host header and gRPC authority given an endpoint and default endpoint.
@_spi(GoogleCloudInternal)
public enum _Host {
  public static let defaultUniverseDomain = "googleapis.com"
  private static let defaultSuffix = ".\(defaultUniverseDomain)"

  /// Resolves the universe domain from `ClientOptions` or `GOOGLE_CLOUD_UNIVERSE_DOMAIN`.
  ///
  /// Precedence:
  /// 1. `options.universeDomain` (if non-empty)
  /// 2. `environment["GOOGLE_CLOUD_UNIVERSE_DOMAIN"]` (if non-empty)
  /// 3. `defaultUniverseDomain` (`"googleapis.com"`)
  public static func resolveUniverseDomain(options: ClientOptions) -> String {
    resolveUniverseDomain(
      options: options,
      environment: ProcessInfo.processInfo.environment
    )
  }

  public static func resolveUniverseDomain(
    options: ClientOptions,
    environment: [String: String]
  ) -> String {
    if let configured = options.universeDomain, !configured.isEmpty {
      return configured
    }
    if let envDomain = environment["GOOGLE_CLOUD_UNIVERSE_DOMAIN"], !envDomain.isEmpty {
      return envDomain
    }
    return defaultUniverseDomain
  }

  /// Resolves the effective endpoint string given an optional custom `endpoint`, the service's
  /// `defaultEndpoint`, and the resolved `universeDomain`.
  ///
  /// When `endpoint` is `nil` and `universeDomain` differs from `googleapis.com`, replaces
  /// `.googleapis.com` in the host of `defaultEndpoint` with `.\(universeDomain)`.
  public static func endpoint(
    endpoint: String?,
    defaultEndpoint: String,
    universeDomain: String = defaultUniverseDomain
  ) throws -> String {
    if let endpoint {
      return endpoint
    }
    if universeDomain == defaultUniverseDomain {
      return defaultEndpoint
    }
    if defaultEndpoint.hasPrefix("/") {
      throw ClientError.invalidEndpoint(defaultEndpoint)
    }
    let hasScheme = defaultEndpoint.contains("://")
    guard
      var components = URLComponents(string: normalizeEndpoint(defaultEndpoint)),
      let defaultHost = components.host,
      !defaultHost.isEmpty
    else {
      throw ClientError.invalidEndpoint(defaultEndpoint)
    }
    guard defaultHost.hasSuffix(defaultSuffix) else {
      return defaultEndpoint
    }
    let service = String(defaultHost.dropLast(defaultSuffix.count))
    guard !service.isEmpty else {
      return defaultEndpoint
    }
    let targetHost = "\(service).\(universeDomain)"
    components.host = targetHost
    guard
      let resolved = components.string,
      let parsed = URLComponents(string: normalizeEndpoint(resolved)),
      parsed.host == targetHost
    else {
      throw ClientError.invalidEndpoint(targetHost)
    }
    if !hasScheme, let scheme = components.scheme {
      let prefix = "\(scheme)://"
      if resolved.hasPrefix(prefix) {
        return String(resolved.dropFirst(prefix.count))
      }
    }
    return resolved
  }

  /// Calculate the HTTP `Host` header given the custom endpoint, default endpoint, and universe domain.
  ///
  /// Regional and locational endpoints matching the service are detected and used as the host.
  /// For VIPs, PSC, and private networks (such as `private.googleapis.com`), the service host is used.
  public static func header(
    endpoint: String?,
    defaultEndpoint: String,
    universeDomain: String = defaultUniverseDomain
  ) throws -> String {
    try originAndHeader(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    ).header
  }

  /// Calculate the gRPC authority given the custom endpoint, default endpoint, and universe domain.
  public static func authority(
    endpoint: String?,
    defaultEndpoint: String,
    universeDomain: String = defaultUniverseDomain
  ) throws -> String {
    try originAndHeader(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    ).authority
  }

  /// Extracts the `<service>` label from a canonical `<service>.googleapis.com` default endpoint.
  private static func extractService(from defaultEndpoint: String) -> String? {
    guard !defaultEndpoint.hasPrefix("/"),
      let components = URLComponents(string: normalizeEndpoint(defaultEndpoint)),
      let defaultHost = components.encodedHost?.lowercased(),
      defaultHost.hasSuffix(defaultSuffix)
    else {
      return nil
    }
    let service = String(defaultHost.dropLast(defaultSuffix.count))
    return !service.isEmpty && !service.contains(".") ? service : nil
  }

  /// Returns `true` when `host` matches a regional (`<service>.<region>.rep.<universeDomain>`) or
  /// locational (`<region>-<service>.<universeDomain>`) hostname for `service` in `universeDomain`.
  private static func isRegionalServiceHost(
    _ host: String,
    service: String,
    universeDomain: String
  ) -> Bool {
    let suffix = ".\(universeDomain)"
    guard !universeDomain.isEmpty, host.hasSuffix(suffix) else { return false }
    let prefix = host.dropLast(suffix.count)
    let parts = prefix.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 3 && parts[0] == service && !parts[1].isEmpty && parts[2] == "rep" {
      return true
    }
    if parts.count == 1 && parts[0].hasSuffix("-\(service)") {
      return !parts[0].dropLast(service.count + 1).isEmpty
    }
    return false
  }

  /// Validates an absolute session `uri` against the client's `baseURL`, `defaultEndpoint`, and
  /// `universeDomain`, returning the outbound request `URLComponents` and HTTP `Host` header.
  ///
  /// Routing rules:
  /// - **Exact origin match** (`scheme`, `host`, and effective `port` match `baseURL`): connects to
  ///   `baseURL` and sends `defaultHostHeader` (covers default, regional, emulator, and custom
  ///   proxy endpoints).
  /// - **Same-universe service or regional host from a non-regional universe `baseURL`**:
  ///   - When `baseURL` is the global `<service>.<universeDomain>` endpoint, updates the connection
  ///     host (`components.encodedHost`) to follow regional/locational hosts in the same universe.
  ///   - When `baseURL` is a VPC-SC or PSC endpoint (such as `private.<universeDomain>`,
  ///     `restricted.<universeDomain>`, or `<psc>.p.<universeDomain>`), keeps `baseURL` as the
  ///     connection target while setting `hostHeader` to the session URI's target service host.
  /// - **Regional `baseURL` isolation**: a client pinned to a regional/locational endpoint rejects
  ///   session URIs targeting the global host or a different region.
  ///
  /// - Parameters:
  ///   - uri: The absolute session URI to validate (for example, from an HTTP `Location` header).
  ///   - baseURL: The client's validated base endpoint `URLComponents`.
  ///   - defaultEndpoint: The service's canonical default endpoint (`https://<service>.googleapis.com`).
  ///   - universeDomain: The client's resolved universe domain (compared case-sensitively per AIP-4110).
  ///   - defaultHostHeader: The client's precomputed HTTP `Host` header for `baseURL`.
  /// - Returns: The outbound request `URLComponents` and its HTTP `Host` header value.
  /// - Throws: `RequestError.badURL(uri)` if `uri` is malformed or relative, contains userinfo, a
  ///   fragment, a percent-encoded host, or a `//`-prefixed path, uses a different scheme (such as
  ///   an `https` to `http` downgrade) or invalid/disallowed port, or targets an untrusted host,
  ///   different service, different region (when pinned), or different universe domain.
  static func resolveRequestURI(
    _ uri: String,
    baseURL: URLComponents,
    defaultEndpoint: String,
    universeDomain: String,
    defaultHostHeader: String
  ) throws -> (components: URLComponents, hostHeader: String) {
    // Reject relative or unparseable URIs, embedded credentials, fragments, percent-encoded host
    // characters (which could smuggle ports or path separators into `Host`), and `//`-prefixed
    // paths (which `URLComponents.url` would reject or reinterpret as an authority).
    guard let parsed = URLComponents(string: uri, encodingInvalidCharacters: false),
      parsed.user == nil,
      parsed.password == nil,
      parsed.fragment == nil,
      let rawScheme = parsed.scheme,
      let encodedHost = parsed.encodedHost,
      !encodedHost.isEmpty,
      !encodedHost.contains("%"),
      parsed.host != nil,
      !parsed.percentEncodedPath.hasPrefix("//"),
      let rawBaseScheme = baseURL.scheme,
      let baseEncodedHost = baseURL.encodedHost
    else {
      throw RequestError.badURL(uri)
    }

    // Enforce exact scheme match with `baseURL` so an `https` client never downgrades to `http`
    // (and an `http` emulator client rejects unexpected `https` URIs).
    let uriScheme = rawScheme.lowercased()
    let baseScheme = rawBaseScheme.lowercased()
    guard uriScheme == baseScheme else {
      throw RequestError.badURL(uri)
    }

    // Normalize implicit default ports (443 for `https`, 80 for `http`) and reject out-of-range
    // port numbers before comparing origins.
    let defaultPort = (uriScheme == "https") ? 443 : 80
    if let port = parsed.port, !(1...65535).contains(port) {
      throw RequestError.badURL(uri)
    }
    let uriPort = parsed.port ?? defaultPort
    let basePort = baseURL.port ?? defaultPort
    let uriHost = encodedHost.lowercased()
    let baseHost = baseEncodedHost.lowercased()

    // Start from `baseURL` so custom endpoints, VPC-SC VIPs, and PSC endpoints preserve their
    // configured connection origin (`scheme`, `host`, `port`) unless explicitly redirected to a
    // regional service host below.
    var out = baseURL
    let resolvedHostHeader: String

    if uriHost == baseHost && uriPort == basePort {
      // Same origin as `baseURL`: keep `baseURL`'s connection target and default `Host` header.
      resolvedHostHeader = defaultHostHeader
    } else if !universeDomain.isEmpty,
      let service = extractService(from: defaultEndpoint),
      baseHost.hasSuffix(".\(universeDomain)"),
      !isRegionalServiceHost(baseHost, service: service, universeDomain: universeDomain),
      uriHost == "\(service).\(universeDomain)"
        || isRegionalServiceHost(uriHost, service: service, universeDomain: universeDomain),
      uriPort == defaultPort || uriPort == basePort
    {
      // `baseURL` is a non-regional host in `universeDomain` (either `<service>.<universeDomain>`
      // or a VPC-SC / PSC endpoint), and `uri` targets the global or regional `<service>` host in
      // that same universe. Connect directly to `uriHost` only from the global service endpoint;
      // VPC-SC and PSC clients keep connecting via `baseURL` while sending `uriHost` in `Host`.
      if baseHost == "\(service).\(universeDomain)" {
        out.encodedHost = uriHost
      }
      resolvedHostHeader = uriHost
    } else {
      throw RequestError.badURL(uri)
    }

    // Replace `baseURL`'s path and query with the session URI's values, escaping `;` to match
    // `_HTTPClient`'s query encoding and clearing any query if the session URI has none.
    out.percentEncodedPath = parsed.percentEncodedPath
    out.percentEncodedQuery = parsed.percentEncodedQuery?.replacingOccurrences(of: ";", with: "%3B")
    guard out.url != nil else {
      throw RequestError.badURL(uri)
    }
    return (components: out, hostHeader: resolvedHostHeader)
  }

  private static func normalizeEndpoint(_ endpoint: String) -> String {
    endpoint.contains("://") ? endpoint : "https://\(endpoint)"
  }

  private static func originAndHeader(
    endpoint: String?,
    defaultEndpoint: String,
    universeDomain: String
  ) throws -> (authority: String, header: String) {
    if defaultEndpoint.hasPrefix("/") {
      throw ClientError.invalidEndpoint(defaultEndpoint)
    }

    guard let defaultComponents = URLComponents(string: normalizeEndpoint(defaultEndpoint)),
      let defaultHost = defaultComponents.host, !defaultHost.isEmpty
    else {
      throw ClientError.invalidEndpoint(defaultEndpoint)
    }

    guard defaultHost.hasSuffix(defaultSuffix) else {
      // Emulators, endpoint showcase and/or test servers pass localhost and
      // should fallback to use the passed-in service host.
      let authority = defaultComponents.port.map { "\(defaultHost):\($0)" } ?? defaultHost
      return (authority: authority, header: defaultHost)
    }

    let service = String(defaultHost.dropLast(defaultSuffix.count))
    guard !service.isEmpty else {
      let authority = defaultComponents.port.map { "\(defaultHost):\($0)" } ?? defaultHost
      return (authority: authority, header: defaultHost)
    }

    guard let endpoint = endpoint, !endpoint.isEmpty else {
      // No endpoint provided, use the default service host at the universe domain.
      let host = "\(service).\(universeDomain)"
      return (authority: host, header: host)
    }

    if endpoint.hasPrefix("/") {
      throw ClientError.invalidEndpoint(endpoint)
    }

    guard let customComponents = URLComponents(string: normalizeEndpoint(endpoint)),
      let customHost = customComponents.host, !customHost.isEmpty
    else {
      throw ClientError.invalidEndpoint(endpoint)
    }

    let universeSuffix = ".\(universeDomain)"
    let prefix: String
    let effectiveUniverseDomain: String

    if customHost.hasSuffix(universeSuffix) {
      prefix = String(customHost.dropLast(universeSuffix.count))
      effectiveUniverseDomain = universeDomain
    } else if customHost.hasSuffix(defaultSuffix) {
      prefix = String(customHost.dropLast(defaultSuffix.count))
      effectiveUniverseDomain = defaultUniverseDomain
    } else {
      // Not a GCP universe domain. Use the endpoint override.
      let authority = customComponents.port.map { "\(customHost):\($0)" } ?? customHost
      return (authority: authority, header: customHost)
    }

    let parts = prefix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 3 where parts[2] == "rep" && parts[0] == service:
      // This is a regional endpoint: `{service}.{region}.rep.googleapis.com`.
      return (authority: customHost, header: customHost)
    case 1:
      // This is a locational endpoint: `{region}-{service}.googleapis.com`.
      let location = parts[0]
      if location.hasSuffix("-\(service)") {
        let region = String(location.dropLast("-\(service)".count))
        if !region.isEmpty {
          return (authority: customHost, header: customHost)
        }
      }
      // Fallback for VPC-SC / PSC or non-matching service
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    default:
      // Fallback for VPC-SC / PSC
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    }
  }
}
