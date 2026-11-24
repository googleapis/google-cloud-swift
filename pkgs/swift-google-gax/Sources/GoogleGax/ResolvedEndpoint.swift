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
    let parsedDefault = try Self.parseEndpoint(
      defaultEndpoint,
      allowsBareHost: allowsBareHost
    )
    let defaultSuffix = ".\(_UniverseDomain.defaultRawValue)"
    let extractedService: String?
    if parsedDefault.host.hasSuffix(defaultSuffix) {
      let candidate = String(parsedDefault.host.dropLast(defaultSuffix.count))
      extractedService = candidate.isEmpty ? nil : candidate
    } else {
      extractedService = nil
    }

    let resolvedBaseURL: URLComponents
    if let endpoint {
      resolvedBaseURL = try Self.parseEndpoint(
        endpoint,
        allowsBareHost: allowsBareHost
      ).components
    } else if !universeDomain.isDefault, let service = extractedService {
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

    let resolvedOrigin = Self.originAndHeader(
      hasCustomEndpoint: endpoint != nil,
      baseURL: resolvedBaseURL,
      defaultComponents: parsedDefault.components,
      defaultHost: parsedDefault.host,
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

  private static func parseEndpoint(
    _ endpoint: String,
    allowsBareHost: Bool
  ) throws -> (components: URLComponents, host: String) {
    guard !endpoint.isEmpty, !endpoint.hasPrefix("/") else {
      throw ClientError.invalidEndpoint(endpoint)
    }
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
    parsed.scheme = scheme
    parsed.queryItems = nil
    parsed.path = ""
    return (components: parsed, host: host)
  }

  private static func originAndHeader(
    hasCustomEndpoint: Bool,
    baseURL: URLComponents,
    defaultComponents: URLComponents,
    defaultHost: String,
    service: String?,
    universeDomain: _UniverseDomain
  ) -> (authority: String, header: String) {
    guard let service else {
      // Emulators, Showcase, and local test servers pass non-googleapis.com default endpoints
      // (such as localhost) and fall back to the default endpoint's host/authority.
      let authority = defaultComponents.port.map { "\(defaultHost):\($0)" } ?? defaultHost
      return (authority: authority, header: defaultHost)
    }

    guard hasCustomEndpoint else {
      let host = "\(service).\(universeDomain.rawValue)"
      return (authority: host, header: host)
    }

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
      // Fallback for VPC-SC / PSC or non-matching service.
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    default:
      // Fallback for VPC-SC / PSC.
      let fallback = "\(service).\(effectiveUniverseDomain)"
      return (authority: fallback, header: fallback)
    }
  }
}
