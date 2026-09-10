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
