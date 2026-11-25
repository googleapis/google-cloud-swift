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
@_spi(GoogleCloudInternal) public import GoogleAuth

/// Encapsulates a validated client endpoint, its universe domain, HTTP `Host` header, and gRPC
/// `:authority` resolved in a single pass.
@_spi(GoogleCloudInternal)
public struct _ResolvedEndpoint: Sendable, Equatable {
  /// Validated base `URLComponents` (`http` or `https` scheme, non-empty `host`, empty `path`,
  /// and `nil` `queryItems`).
  public let baseURL: URLComponents

  /// The canonical default endpoint supplied by the service client (for example,
  /// `"https://storage.googleapis.com"`).
  public let defaultEndpoint: String

  /// The `<service>` prefix extracted when `defaultEndpoint`'s host ends in `.googleapis.com`,
  /// or `nil` for non-universe default endpoints (such as `localhost`).
  public let service: String?

  /// The resolved universe domain for this client.
  public let universeDomain: _UniverseDomain

  /// Precomputed HTTP `Host` header value for requests to `baseURL`.
  public let hostHeader: String

  /// Precomputed gRPC HTTP/2 `:authority` value for connections to `baseURL`.
  public let authority: String

  /// Whether `baseURL` uses TLS (`https`).
  public var isSecure: Bool {
    baseURL.scheme == "https"
  }

  /// The validated target hostname or bare IP literal from `baseURL` (with surrounding RFC 3986
  /// IPv6 `[` and `]` brackets stripped so DNS/socket resolvers such as `getaddrinfo` accept it).
  public var host: String {
    Self.unbracketedHost(baseURL.host ?? "")
  }

  /// The target TCP port from `baseURL`, defaulting to `443` for `https` and `80` for `http`.
  public var port: Int {
    baseURL.port ?? (isSecure ? 443 : 80)
  }

  /// Resolves an endpoint from `ClientOptions` and `ProcessInfo.processInfo.environment`.
  public init(
    options: ClientOptions,
    defaultEndpoint: String,
    allowsBareHost: Bool = false
  ) throws {
    try self.init(
      options: options,
      defaultEndpoint: defaultEndpoint,
      allowsBareHost: allowsBareHost,
      environment: ProcessInfo.processInfo.environment
    )
  }

  /// Resolves an endpoint from `ClientOptions` and an injectable `environment` dictionary.
  public init(
    options: ClientOptions,
    defaultEndpoint: String,
    allowsBareHost: Bool = false,
    environment: [String: String]
  ) throws {
    let universeDomain = _UniverseDomain.resolve(
      configured: options.universeDomain,
      environment: environment
    )
    try self.init(
      endpoint: options.endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain,
      allowsBareHost: allowsBareHost
    )
  }

  /// Resolves and validates `baseURL`, `hostHeader`, and `authority` from an optional custom
  /// `endpoint`, the service's `defaultEndpoint`, and the resolved `universeDomain`.
  public init(
    endpoint: String?,
    defaultEndpoint: String,
    universeDomain: _UniverseDomain = .default,
    allowsBareHost: Bool = false
  ) throws {
    // Parse `defaultEndpoint` upfront and extract `<service>` when it is a standard
    // `<service>.googleapis.com` host. Non-universe defaults (e.g. Showcase `localhost:7469`)
    // yield `nil` so universe substitution and `<service>` header rewriting are skipped.
    let parsedDefault = try Self.parseEndpoint(
      defaultEndpoint,
      allowsBareHost: allowsBareHost
    )
    let defaultSuffix = ".\(_UniverseDomain.defaultRawValue)"
    let defaultHostLower = parsedDefault.host.lowercased()
    let extractedService: String?
    if defaultHostLower.hasSuffix(defaultSuffix) {
      let candidate = String(defaultHostLower.dropLast(defaultSuffix.count))
      extractedService = candidate.isEmpty ? nil : candidate
    } else {
      extractedService = nil
    }

    let resolvedBaseURL: URLComponents
    if let endpoint {
      // Explicit `ClientOptions.endpoint` overrides universe domain host substitution.
      resolvedBaseURL = try Self.parseEndpoint(
        endpoint,
        allowsBareHost: allowsBareHost
      ).components
    } else if !universeDomain.isDefault, let service = extractedService {
      // Substitute `<service>.<universeDomain>` and parse strictly with
      // `encodingInvalidCharacters: false` so non-ASCII/IDNA or malformed `universeDomain` values
      // cannot Punycode-round-trip or inject ports, userinfo, paths, queries, or fragments.
      let scheme = parsedDefault.components.scheme ?? "https"
      let portSuffix = parsedDefault.components.port.map { ":\($0)" } ?? ""
      let targetHost = "\(service).\(universeDomain.rawValue)"
      let candidateString = "\(scheme)://\(targetHost)\(portSuffix)"
      guard
        let reparsed = URLComponents(string: candidateString, encodingInvalidCharacters: false),
        reparsed.scheme == scheme,
        reparsed.host == targetHost,
        reparsed.percentEncodedHost == targetHost,
        reparsed.port == parsedDefault.components.port,
        reparsed.user == nil,
        reparsed.password == nil,
        reparsed.percentEncodedPath.isEmpty,
        reparsed.percentEncodedQuery == nil,
        reparsed.percentEncodedFragment == nil,
        reparsed.url != nil
      else {
        throw ClientError.invalidEndpoint(targetHost)
      }
      resolvedBaseURL = reparsed
    } else {
      resolvedBaseURL = parsedDefault.components
    }

    // Precompute the outbound HTTP `Host` header and gRPC `:authority` once at init.
    let resolvedOrigin = Self.originAndHeader(
      hasCustomEndpoint: endpoint != nil,
      baseURL: resolvedBaseURL,
      service: extractedService,
      universeDomain: universeDomain
    )

    self.baseURL = resolvedBaseURL
    self.defaultEndpoint = defaultEndpoint
    self.service = extractedService
    self.universeDomain = universeDomain
    self.hostHeader = resolvedOrigin.header
    self.authority = resolvedOrigin.authority
  }

  /// Validates an absolute session `uri` against this endpoint's `baseURL`, `service`, and
  /// `universeDomain`, returning the outbound request `URLComponents` and HTTP `Host` header.
  ///
  /// Routing rules:
  /// - **Exact origin match** (`scheme`, `host`, and effective `port` match `baseURL`): connects to
  ///   `baseURL` and sends `hostHeader` (covers default, regional, emulator, and custom proxy
  ///   endpoints).
  /// - **Same-universe service or regional host from a non-regional universe `baseURL`**:
  ///   - When `baseURL` is the global `<service>.<universeDomain>` endpoint, updates the connection
  ///     host (`components.host`) to follow regional/locational hosts in the same universe.
  ///   - When `baseURL` is a VPC-SC or PSC endpoint (such as `private.<universeDomain>`,
  ///     `restricted.<universeDomain>`, or `<psc>.p.<universeDomain>`), keeps `baseURL` as the
  ///     connection target while setting `hostHeader` to the session URI's target service host.
  /// - **Regional `baseURL` isolation**: a client pinned to a regional/locational endpoint rejects
  ///   session URIs targeting the global host or a different region.
  ///
  /// - Parameter uri: The absolute session URI to validate (for example, from an HTTP `Location`
  ///   header).
  /// - Returns: The outbound request `URLComponents` and its HTTP `Host` header value.
  /// - Throws: `RequestError.badURL(uri)` if `uri` is malformed or relative, contains userinfo or a
  ///   fragment, uses a different scheme (such as an `https` to `http` downgrade) or disallowed
  ///   port, or targets an untrusted host, different service, different region (when pinned), or
  ///   different universe domain.
  public func resolveRequestURI(
    _ uri: String
  ) throws -> (components: URLComponents, hostHeader: String) {
    // Reject relative or unparsable URIs, embedded credentials, fragments, percent-encoded hosts,
    // and scheme mismatches (preventing `https` to `http` downgrades).
    guard let parsed = URLComponents(string: uri, encodingInvalidCharacters: false),
      parsed.user == nil,
      parsed.password == nil,
      parsed.percentEncodedFragment == nil,
      let uriScheme = parsed.scheme?.lowercased(),
      let percentEncodedHost = parsed.percentEncodedHost,
      !percentEncodedHost.isEmpty,
      !percentEncodedHost.contains("%"),
      let rawParsedHost = parsed.host,
      !Self.unbracketedHost(rawParsedHost).isEmpty,
      let baseScheme = self.baseURL.scheme?.lowercased(),
      let rawSelfHost = self.baseURL.host,
      uriScheme == baseScheme
    else {
      throw RequestError.badURL(uri)
    }

    let rawURIHost = Self.bracketedHost(rawParsedHost)
    let rawBaseHost = Self.bracketedHost(rawSelfHost)
    let uriHostLower = rawURIHost.lowercased()
    let baseHostLower = rawBaseHost.lowercased()

    let defaultPort = (uriScheme == "https") ? 443 : 80
    let uriPort = parsed.port ?? defaultPort
    let basePort = self.baseURL.port ?? defaultPort

    // Start from `baseURL` so custom endpoints, VPC-SC VIPs, and PSC endpoints preserve their
    // configured connection origin (`scheme`, `host`, `port`) unless explicitly redirected to a
    // regional service host below.
    var out = self.baseURL
    let resolvedHostHeader: String
    let universeRaw = self.universeDomain.rawValue
    let universeSuffix = ".\(universeRaw)"
    let universeSuffixLower = universeSuffix.lowercased()

    if uriHostLower == baseHostLower && uriPort == basePort {
      // Same origin as `baseURL`: keep `baseURL`'s connection target and default `Host` header.
      resolvedHostHeader = self.hostHeader
    } else if !universeRaw.isEmpty,
      let service = self.service,
      !service.contains("."),
      rawBaseHost.hasSuffix(universeSuffix)
        || (self.universeDomain.isDefault && baseHostLower.hasSuffix(universeSuffixLower)),
      rawURIHost.hasSuffix(universeSuffix)
        || (self.universeDomain.isDefault && uriHostLower.hasSuffix(universeSuffixLower)),
      uriPort == defaultPort || uriPort == basePort
    {
      let basePrefixLower = String(baseHostLower.dropLast(universeSuffixLower.count))
      let uriPrefixLower = String(uriHostLower.dropLast(universeSuffixLower.count))
      guard
        !Self.isRegionalServicePrefix(basePrefixLower, service: service),
        uriPrefixLower == service || Self.isRegionalServicePrefix(uriPrefixLower, service: service)
      else {
        throw RequestError.badURL(uri)
      }
      // `baseURL` is a non-regional host in `universeDomain` (either `<service>.<universeDomain>`
      // or a VPC-SC / PSC endpoint), and `uri` targets the global or regional `<service>` host in
      // that same universe. Connect directly to `targetHost` only from the global service endpoint;
      // VPC-SC and PSC clients keep connecting via `baseURL` while sending `targetHost` in `Host`.
      let targetHost = "\(uriPrefixLower).\(universeRaw)"
      if basePrefixLower == service {
        out.host = targetHost
        out.port = (uriPort == defaultPort) ? nil : uriPort
      }
      resolvedHostHeader = targetHost
    } else {
      throw RequestError.badURL(uri)
    }

    // Replace `baseURL`'s path and query with the session URI's values, escaping `;` to match
    // `_HTTPClient`'s query encoding and clearing any query if the session URI has none.
    out.percentEncodedPath = parsed.percentEncodedPath
    out.percentEncodedQuery = parsed.percentEncodedQuery?.replacingOccurrences(
      of: ";",
      with: "%3B"
    )
    guard out.url != nil else {
      throw RequestError.badURL(uri)
    }
    return (components: out, hostHeader: resolvedHostHeader)
  }

  /// Returns `true` when a lowercased host prefix (before `.<universeDomain>`) matches a regional
  /// (`<service>.<region>.rep`) or locational (`<region>-<service>`) pattern for `service`.
  private static func isRegionalServicePrefix(
    _ prefix: String,
    service: String
  ) -> Bool {
    let parts = prefix.split(separator: ".", omittingEmptySubsequences: false)
    // Regional Endpoint (REP): `<service>.<region>.rep.<universeDomain>` with non-empty `<region>`.
    if parts.count == 3 && parts[0] == service && !parts[1].isEmpty && parts[2] == "rep" {
      return true
    }
    // Locational endpoint: `<region>-<service>.<universeDomain>` with non-empty `<region>`.
    if parts.count == 1 && parts[0].hasSuffix("-\(service)") {
      return !parts[0].dropLast(service.count + 1).isEmpty
    }
    return false
  }

  /// Strips RFC 3986 surrounding `[` and `]` brackets from an IPv6 host literal, if present.
  private static func unbracketedHost(_ host: String) -> String {
    if host.hasPrefix("[") && host.hasSuffix("]") && host.count >= 2 {
      return String(host.dropFirst().dropLast())
    }
    return host
  }

  /// Formats a host for HTTP `Host` and HTTP/2 `:authority` headers, bracketing IPv6 literals
  /// consistently regardless of whether `URLComponents.host` includes or strips `[` and `]`.
  private static func bracketedHost(_ rawHost: String) -> String {
    let bare = unbracketedHost(rawHost)
    return bare.contains(":") ? "[\(bare)]" : bare
  }

  /// Parses and normalizes a raw endpoint string into clean origin-only `URLComponents` (`http` or
  /// `https` scheme, non-empty `host`, `nil` userinfo/fragment/query, and empty `path`).
  private static func parseEndpoint(
    _ endpoint: String,
    allowsBareHost: Bool
  ) throws -> (components: URLComponents, host: String) {
    // Reject empty strings and leading slashes upfront so `allowsBareHost` never turns a relative
    // path like `"/a/b"` into `"https:///a/b"` or `"https://a/b"`.
    guard !endpoint.isEmpty, !endpoint.hasPrefix("/") else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    // gRPC accepts bare `host[:port]` strings (defaulting to TLS), whereas HTTP requires an
    // explicit `http://` or `https://` scheme.
    let normalized: String
    if endpoint.contains("://") {
      normalized = endpoint
    } else if allowsBareHost {
      normalized = "https://\(endpoint)"
    } else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    guard
      var parsed = URLComponents(string: normalized, encodingInvalidCharacters: false),
      parsed.user == nil,
      parsed.password == nil,
      let scheme = parsed.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let percentEncodedHost = parsed.percentEncodedHost,
      !percentEncodedHost.isEmpty,
      !percentEncodedHost.contains("%"),
      let host = parsed.host,
      !Self.unbracketedHost(host).isEmpty
    else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    // Canonicalize the scheme and strip any path, query, or fragment so callers can compose per-RPC
    // paths and query items onto `baseURL` without inheriting residual components.
    parsed.scheme = scheme
    parsed.queryItems = nil
    parsed.fragment = nil
    parsed.path = ""
    return (components: parsed, host: host)
  }

  /// Computes the gRPC `:authority` pseudo-header and HTTP `Host` header for `baseURL`.
  private static func originAndHeader(
    hasCustomEndpoint: Bool,
    baseURL: URLComponents,
    service: String?,
    universeDomain: _UniverseDomain
  ) -> (authority: String, header: String) {
    guard let service else {
      // Non-googleapis.com default endpoints (such as Showcase or local test servers) use the
      // resolved `baseURL` (either the custom `endpoint` override or `defaultEndpoint`).
      let host = Self.bracketedHost(baseURL.host ?? "")
      let authority = baseURL.port.map { "\(host):\($0)" } ?? host
      return (authority: authority, header: host)
    }

    guard hasCustomEndpoint else {
      // Standard service endpoint without a custom `ClientOptions.endpoint` override.
      let host = "\(service).\(universeDomain.rawValue)"
      return (authority: host, header: host)
    }

    // Match `customHost` against either the configured universe domain (case-sensitively on the
    // universe suffix per AIP-4110) or `.googleapis.com` (case-insensitively, for callers
    // overriding `endpoint` to a VPC-SC VIP or regional `.googleapis.com` host without setting
    // `universeDomain`). Custom hosts outside both universes (emulators, local proxies, `localhost`,
    // IPv6 `[::1]`) keep their literal host (and port in gRPC `:authority`).
    let customHost = Self.bracketedHost(baseURL.host ?? "")
    let customHostLower = customHost.lowercased()
    let universeSuffix = ".\(universeDomain.rawValue)"
    let defaultSuffix = ".\(_UniverseDomain.defaultRawValue)"
    let prefixLower: String
    let effectiveUniverseDomain: String

    if customHost.hasSuffix(universeSuffix) {
      prefixLower = String(customHost.dropLast(universeSuffix.count)).lowercased()
      effectiveUniverseDomain = universeDomain.rawValue
    } else if customHostLower.hasSuffix(defaultSuffix) {
      prefixLower = String(customHostLower.dropLast(defaultSuffix.count))
      effectiveUniverseDomain = _UniverseDomain.defaultRawValue
    } else {
      let authority = baseURL.port.map { "\(customHost):\($0)" } ?? customHost
      return (authority: authority, header: customHost)
    }

    // Regional and locational service hosts retain their regional hostname in `Host` / `:authority`,
    // whereas VPC-SC VIPs (`private.<universe>`, `restricted.<universe>`), PSC endpoints
    // (`<psc>.p.<universe>`), and `www.<universe>` rewrite `Host` / `:authority` to
    // `<service>.<universe>` so Google Frontends route the request to the target service.
    if Self.isRegionalServicePrefix(prefixLower, service: service) {
      let regionalHost = "\(prefixLower).\(effectiveUniverseDomain)"
      return (authority: regionalHost, header: regionalHost)
    }
    let fallback = "\(service).\(effectiveUniverseDomain)"
    return (authority: fallback, header: fallback)
  }
}
