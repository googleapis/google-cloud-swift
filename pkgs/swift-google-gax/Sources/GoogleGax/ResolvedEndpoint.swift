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

  /// The validated target hostname from `baseURL`.
  public var host: String {
    baseURL.host ?? ""
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
      // Substitute `<service>.<universeDomain>` and round-trip through `URLComponents(string:)`
      // to reject malformed `universeDomain` values that would inject ports, userinfo, paths,
      // queries, or fragments into the serialized URL.
      let targetHost = "\(service).\(universeDomain.rawValue)"
      var candidate = parsedDefault.components
      candidate.host = targetHost
      guard
        let candidateString = candidate.string,
        let reparsed = URLComponents(string: candidateString),
        reparsed.host == targetHost,
        reparsed.port == parsedDefault.components.port,
        reparsed.user == nil,
        reparsed.password == nil,
        reparsed.path.isEmpty,
        reparsed.query == nil,
        reparsed.fragment == nil
      else {
        throw ClientError.invalidEndpoint(targetHost)
      }
      resolvedBaseURL = candidate
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
    // Reject relative or unparsable URIs, embedded credentials, fragments, and scheme mismatches
    // (preventing `https` to `http` downgrades).
    guard let parsed = URLComponents(string: uri),
      parsed.user == nil,
      parsed.password == nil,
      parsed.fragment == nil,
      let uriScheme = parsed.scheme?.lowercased(),
      let uriHost = parsed.host?.lowercased(),
      !uriHost.isEmpty,
      let baseScheme = self.baseURL.scheme?.lowercased(),
      let baseHost = self.baseURL.host?.lowercased(),
      uriScheme == baseScheme
    else {
      throw RequestError.badURL(uri)
    }

    let defaultPort = (uriScheme == "https") ? 443 : 80
    let uriPort = parsed.port ?? defaultPort
    let basePort = self.baseURL.port ?? defaultPort

    // Start from `baseURL` so custom endpoints, VPC-SC VIPs, and PSC endpoints preserve their
    // configured connection origin (`scheme`, `host`, `port`) unless explicitly redirected to a
    // regional service host below.
    var out = self.baseURL
    let resolvedHostHeader: String
    let universeRaw = self.universeDomain.rawValue

    if uriHost == baseHost && uriPort == basePort {
      // Same origin as `baseURL`: keep `baseURL`'s connection target and default `Host` header.
      resolvedHostHeader = self.hostHeader
    } else if !universeRaw.isEmpty,
      let service = self.service,
      !service.contains("."),
      baseHost.hasSuffix(".\(universeRaw)"),
      !Self.isRegionalServiceHost(baseHost, service: service, universeDomain: universeRaw),
      uriHost == "\(service).\(universeRaw)"
        || Self.isRegionalServiceHost(uriHost, service: service, universeDomain: universeRaw),
      uriPort == defaultPort || uriPort == basePort
    {
      // `baseURL` is a non-regional host in `universeDomain` (either `<service>.<universeDomain>`
      // or a VPC-SC / PSC endpoint), and `uri` targets the global or regional `<service>` host in
      // that same universe. Connect directly to `uriHost` only from the global service endpoint;
      // VPC-SC and PSC clients keep connecting via `baseURL` while sending `uriHost` in `Host`.
      if baseHost == "\(service).\(universeRaw)" {
        out.host = uriHost
      }
      resolvedHostHeader = uriHost
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

  /// Parses and normalizes a raw endpoint string into clean origin-only `URLComponents` (`http` or
  /// `https` scheme, non-empty `host`, empty `path`, and `nil` `queryItems`).
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
      var parsed = URLComponents(string: normalized),
      let scheme = parsed.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = parsed.host,
      !host.isEmpty
    else {
      throw ClientError.invalidEndpoint(endpoint)
    }
    // Canonicalize the scheme and strip any path or query so callers can compose per-RPC paths
    // and query items onto `baseURL` without inheriting residual components.
    parsed.scheme = scheme
    parsed.queryItems = nil
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
      let host = baseURL.host ?? ""
      let authority = baseURL.port.map { "\(host):\($0)" } ?? host
      return (authority: authority, header: host)
    }

    guard hasCustomEndpoint else {
      // Standard service endpoint without a custom `ClientOptions.endpoint` override.
      let host = "\(service).\(universeDomain.rawValue)"
      return (authority: host, header: host)
    }

    // Match `customHost` against either the configured universe domain or `.googleapis.com` (for
    // callers overriding `endpoint` to a VPC-SC VIP or regional `.googleapis.com` host without
    // setting `universeDomain`). Custom hosts outside both universes (emulators, local proxies,
    // `localhost`) keep their literal host (and port in gRPC `:authority`).
    let customHost = baseURL.host ?? ""
    let universeSuffix = ".\(universeDomain.rawValue)"
    let defaultSuffix = ".\(_UniverseDomain.defaultRawValue)"
    let prefix: String
    let effectiveUniverseDomain: String

    if customHost.hasSuffix(universeSuffix) {
      prefix = String(customHost.dropLast(universeSuffix.count))
      effectiveUniverseDomain = universeDomain.rawValue
    } else if customHost.hasSuffix(defaultSuffix) {
      prefix = String(customHost.dropLast(defaultSuffix.count))
      effectiveUniverseDomain = _UniverseDomain.defaultRawValue
    } else {
      let authority = baseURL.port.map { "\(customHost):\($0)" } ?? customHost
      return (authority: authority, header: customHost)
    }

    // Regional and locational service hosts retain their regional hostname in `Host` / `:authority`,
    // whereas VPC-SC VIPs (`private.<universe>`, `restricted.<universe>`), PSC endpoints
    // (`<psc>.p.<universe>`), and `www.<universe>` rewrite `Host` / `:authority` to
    // `<service>.<universe>` so Google Frontends route the request to the target service.
    let parts = prefix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 3 where parts[2] == "rep" && parts[0] == service && !parts[1].isEmpty:
      // Regional endpoint: `{service}.{region}.rep.{universeDomain}`.
      return (authority: customHost, header: customHost)
    case 1:
      // Locational endpoint: `{region}-{service}.{universeDomain}`.
      let location = parts[0]
      if location.hasSuffix("-\(service)") {
        let region = String(location.dropLast("-\(service)".count))
        if !region.isEmpty {
          return (authority: customHost, header: customHost)
        }
      }
      // Fallback for single-label non-locational universe hosts (e.g. `private`, `restricted`, `www`).
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    default:
      // Fallback for multi-label universe hosts (e.g. PSC `<endpoint>.p.<universeDomain>`).
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    }
  }
}
