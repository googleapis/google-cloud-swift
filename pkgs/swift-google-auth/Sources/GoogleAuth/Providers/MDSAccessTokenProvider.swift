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
import NIOHTTP1

/// A `TokenProvider` that fetches short-lived OAuth 2.0 access tokens from the Google Cloud Metadata Service.
///
/// The metadata service is available on Compute Engine VMs, GKE pods, Cloud Run instances, and other
/// GCP compute environments. It exposes an HTTP endpoint at `/computeMetadata/v1/instance/service-accounts/default/token`
/// that issues access tokens for the instance's attached default service account.
///
/// All requests must include the `Metadata-Flavor: Google` HTTP header to prevent SSRF vulnerabilities.
///
/// - SeeAlso: [AIP-4115: Metadata Server](https://google.aip.dev/auth/4115)
struct MDSAccessTokenProvider: TokenProvider, Sendable {
  /// The base URL of the metadata server endpoint, or `nil` to resolve via environment/default.
  let endpoint: URL?

  /// An optional Google Cloud project ID for quota and billing attribution.
  let quotaProjectID: String?

  /// The list of OAuth 2.0 scopes requested for the token.
  let scopes: [String]

  /// The HTTP client used to execute requests against the metadata server.
  let client: AuthHTTPClient

  /// A boolean indicating whether this provider was instantiated as part of ADC discovery.
  let fromADC: Bool

  /// The retry configuration controlling backoff and retry behavior for transient errors.
  let retryConfiguration: RetryConfiguration?

  /// The system environment variables dictionary, inspected for `GCE_METADATA_HOST`.
  let environment: [String: String]

  /// The canonical base endpoint URL for the Google Cloud Compute Engine metadata server.
  static let defaultEndpoint = "http://metadata.google.internal"

  /// Initializes a new instance of `MDSAccessTokenProvider`.
  ///
  /// - Parameters:
  ///   - endpoint: Custom base URL override for the metadata server.
  ///   - quotaProjectID: Optional quota project ID to include in headers.
  ///   - scopes: Scopes requested for the token.
  ///   - retryConfiguration: Retry policy configuration for network requests.
  ///   - client: HTTP client instance.
  ///   - fromADC: Set to `true` if instantiated during ADC resolution.
  ///   - environment: Process environment dictionary.
  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    scopes: [String] = [],
    retryConfiguration: RetryConfiguration? = nil,
    client: AuthHTTPClient = AuthHTTPClient(),
    fromADC: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.endpoint = endpoint
    self.quotaProjectID = nonEmpty(quotaProjectID)
    self.scopes = scopes
    self.retryConfiguration = retryConfiguration
    self.client = client
    self.fromADC = fromADC
    self.environment = environment
  }

  /// Resolves the metadata server base URL.
  ///
  /// Precedence: the explicit `endpoint`, then `GCE_METADATA_HOST`, then `defaultEndpoint`.
  ///
  /// - Parameter hostEnv: The value of `GCE_METADATA_HOST`, if set.
  /// - Returns: The base URL to use for metadata server requests.
  /// - Throws: `CredentialsError.cannotFetchToken` if `GCE_METADATA_HOST` is not a valid URL.
  private func resolveBaseEndpoint(
    hostEnv: String?,
    resource: String = "an access token"
  ) throws -> URL {
    if let endpoint = self.endpoint {
      return endpoint
    }
    if let hostEnv = hostEnv, !hostEnv.isEmpty {
      // Check explicitly for `http://` or `https://` scheme prefixes rather than `hasPrefix("http")`
      // so hostnames starting with `"http"` (e.g. `http-metadata-proxy.internal:8080`) still get an
      // `http://` scheme prepended instead of having the hostname parsed as the URL scheme.
      let lowercased = hostEnv.lowercased()
      let hasScheme = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
      let hostString = hasScheme ? hostEnv : "http://\(hostEnv)"
      guard
        let url = URL(string: hostString),
        let host = url.host,
        !host.isEmpty,
        url.path.isEmpty || url.path == "/",
        url.query == nil,
        url.fragment == nil
      else {
        // Wrap `CredentialsError.parseError` inside `.cannotFetchToken` so callers always receive
        // `.cannotFetchToken` from `fetchToken()`, while `AuthHTTPError.isRetryable(_:)` unwraps
        // the underlying `.parseError` and treats invalid configuration as a permanent failure.
        throw CredentialsError.cannotFetchToken(
          message: "Could not fetch \(resource) from the metadata server.",
          underlyingError: CredentialsError.parseError(
            "Invalid GCE_METADATA_HOST URL: '\(hostEnv)'")
        )
      }
      return url
    }
    return URL(string: Self.defaultEndpoint)!
  }

  /// Explains a failure to fetch a token from the metadata server.
  ///
  /// - Parameters:
  ///   - isADCFallback: Whether the credentials reached the metadata server as the last step of
  ///     Application Default Credentials discovery, rather than by explicit configuration.
  ///   - endpoint: The metadata server endpoint that was contacted.
  /// - Returns: A human-readable message describing the failure and what to verify next.
  private static func errorMessage(
    isADCFallback: Bool,
    endpoint: URL,
    resource: String = "an access token"
  ) -> String {
    let summary =
      "Could not fetch \(resource) from the metadata server at \(endpoint.absoluteString)."
    if isADCFallback {
      return """
        \(summary)
        Application Default Credentials (ADC) did not find any other credentials and fell back to
        the metadata server. The most common reason for this failure is that the application is not
        running in a Google Cloud environment and no local credentials have been configured. To set
        up local credentials, run `gcloud auth application-default login`. More information on how
        to authenticate client libraries can be found at
        https://cloud.google.com/docs/authentication/client-libraries
        """
    }
    return """
      \(summary)
      Verify that a metadata server is running and reachable at that endpoint. The default endpoint
      (\(Self.defaultEndpoint)) can be overridden with the `GCE_METADATA_HOST` environment variable.
      """
  }

  /// Verifies that the metadata server response carries `Metadata-Flavor: Google`.
  ///
  /// Splits each `Metadata-Flavor` header value on commas and requires a non-empty list where
  /// every element (trimmed of HTTP optional whitespace `SP` and `HTAB`) ASCII case-insensitively
  /// equals `"google"`.
  private static func verifyMetadataFlavor(_ responseHeaders: HTTPHeaders) throws {
    let values = responseHeaders["Metadata-Flavor"]
    let elements = values.flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
    guard !elements.isEmpty, elements.allSatisfy(Self.isGoogleMetadataFlavorValue) else {
      throw CredentialsError.parseError(
        "Metadata server response is missing required 'Metadata-Flavor: Google' header"
      )
    }
  }

  /// Returns `true` when `value` (trimmed of HTTP optional whitespace `SP` and `HTAB`) ASCII
  /// case-insensitively equals `"google"`.
  private static func isGoogleMetadataFlavorValue(_ value: Substring) -> Bool {
    let utf8 = value.utf8
    guard
      let start = utf8.firstIndex(where: { !Self.isHTTPOWS($0) }),
      let end = utf8.lastIndex(where: { !Self.isHTTPOWS($0) })
    else {
      return false
    }
    return utf8[start...end].elementsEqual("google".utf8) { lhs, rhs in
      Self.toASCIILower(lhs) == rhs
    }
  }

  /// Trims leading and trailing ASCII spaces, horizontal tabs, carriage returns, and line feeds
  /// from a plain-text metadata response without stripping non-ASCII whitespace or other control
  /// characters.
  private static func trimASCIIWhitespaceAndNewlines(_ value: String) -> String {
    let utf8 = value.utf8
    guard
      let start = utf8.firstIndex(where: { !Self.isASCIILineWhitespace($0) }),
      let end = utf8.lastIndex(where: { !Self.isASCIILineWhitespace($0) })
    else {
      return ""
    }
    return String(decoding: utf8[start...end], as: UTF8.self)
  }

  private static func isHTTPOWS(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09
  }

  private static func isASCIILineWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  private static func toASCIILower(_ byte: UInt8) -> UInt8 {
    (0x41...0x5A).contains(byte) ? byte + 0x20 : byte
  }

  /// Validates that `domain` is a strict RFC 1035 / RFC 1123 / RFC 3696 DNS domain name suitable
  /// for interpolating into service hostnames (`https://sts.\(domain)`).
  private static func isValidUniverseDomain(_ domain: String) -> Bool {
    let utf8 = domain.utf8
    guard (1...253).contains(utf8.count) else {
      return false
    }
    let dot = UInt8(ascii: ".")
    let hyphen = UInt8(ascii: "-")
    let labels = utf8.split(separator: dot, omittingEmptySubsequences: false)
    guard labels.count >= 2 else {
      return false
    }
    for label in labels {
      guard
        (1...63).contains(label.count),
        label.first != hyphen,
        label.last != hyphen,
        label.allSatisfy(Self.isDNSLabelByte)
      else {
        return false
      }
    }
    // RFC 1123 §2.1 / RFC 3696 §2: the final TLD label cannot be all-numeric (must contain at
    // least one ASCII letter), rejecting IPv4 dotted-quad literals and numeric TLDs.
    guard let tld = labels.last, tld.contains(where: Self.isASCIIAlpha) else {
      return false
    }
    guard
      let components = URLComponents(
        string: "https://sts.\(domain)",
        encodingInvalidCharacters: false
      ),
      components.encodedHost?.lowercased() == "sts.\(domain.lowercased())",
      components.url != nil
    else {
      return false
    }
    return true
  }

  private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
    (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
  }

  private static func isDNSLabelByte(_ byte: UInt8) -> Bool {
    Self.isASCIIAlpha(byte) || (0x30...0x39).contains(byte) || byte == 0x2D
  }

  /// Fetches a fresh OAuth 2.0 access token from the metadata server.
  ///
  /// Resolves the base URL using `endpoint`, `GCE_METADATA_HOST`, or `defaultEndpoint`, appends the token path
  /// `/computeMetadata/v1/instance/service-accounts/default/token`, sends `Metadata-Flavor: Google`, and verifies
  /// that the response includes `Metadata-Flavor: Google`.
  ///
  /// - Returns: A valid `AccessToken` containing the access token string and expiration date.
  /// - Throws: `CredentialsError.cannotFetchToken` if the metadata server is unreachable, omits `Metadata-Flavor: Google`, or returns an error.
  @concurrent
  func fetchToken() async throws -> AccessToken {
    let hostEnv = self.environment["GCE_METADATA_HOST"]
    let baseEndpoint = try self.resolveBaseEndpoint(hostEnv: hostEnv)
    let isADCFallback =
      self.fromADC && self.endpoint == nil && (hostEnv == nil || hostEnv?.isEmpty == true)

    guard
      var urlComponents = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false),
      let host = urlComponents.host,
      !host.isEmpty
    else {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(isADCFallback: isADCFallback, endpoint: baseEndpoint),
        underlyingError: CredentialsError.parseError(
          "Invalid metadata server endpoint URL: '\(baseEndpoint.absoluteString)'")
      )
    }
    urlComponents.path = "/computeMetadata/v1/instance/service-accounts/default/token"

    if !self.scopes.isEmpty {
      urlComponents.queryItems = [
        URLQueryItem(name: "scopes", value: self.scopes.joined(separator: ","))
      ]
    }

    guard let url = urlComponents.url else {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(isADCFallback: isADCFallback, endpoint: baseEndpoint),
        underlyingError: CredentialsError.parseError(
          "Invalid metadata server endpoint URL: '\(baseEndpoint.absoluteString)'")
      )
    }

    let headers = ["Metadata-Flavor": "Google"]

    struct TokenResponse: Decodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }

    let fetchOperation: @Sendable () async throws -> AccessToken = {
      let (response, responseHeaders): (TokenResponse, HTTPHeaders) =
        try await self.client.getWithHeaders(url: url, headers: headers)
      try Self.verifyMetadataFlavor(responseHeaders)
      let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
      return AccessToken(
        token: response.accessToken,
        tokenType: response.tokenType,
        expirationDate: expiration
      )
    }

    // ADC falls back to the metadata server when it finds no other credentials. Outside Google
    // Cloud that fallback cannot succeed, so fail fast instead of retrying.
    do {
      if isADCFallback {
        return try await fetchOperation()
      } else {
        return try await RetryEngine.retry(
          configuration: self.retryConfiguration ?? .defaultConfiguration,
          isRetryable: AuthHTTPError.isRetryable,
          operation: fetchOperation
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let AuthHTTPError.unknown(inner) where inner is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(isADCFallback: isADCFallback, endpoint: baseEndpoint),
        underlyingError: error
      )
    }
  }

  /// Queries the metadata server for the attached environment's universe domain.
  ///
  /// Requests `/computeMetadata/v1/universe/universe-domain` with `Metadata-Flavor: Google`,
  /// verifies `Metadata-Flavor: Google` on 2xx responses, and validates any non-empty domain
  /// against strict RFC 1035 / RFC 1123 / RFC 3696 DNS hostname syntax.
  /// Standard Google Default Universe (`googleapis.com`) metadata servers may return HTTP 404
  /// or an empty body for this endpoint; both are treated as `googleapis.com`.
  ///
  /// - Returns: The resolved and validated universe domain string.
  /// - Throws: `CredentialsError.cannotFetchToken` if the metadata server is unreachable, omits `Metadata-Flavor: Google`, returns an invalid domain, or returns an unexpected error.
  @concurrent
  func fetchUniverseDomain() async throws -> String {
    let hostEnv = self.environment["GCE_METADATA_HOST"]
    let baseEndpoint = try self.resolveBaseEndpoint(
      hostEnv: hostEnv,
      resource: "the universe domain"
    )
    let isADCFallback =
      self.fromADC && self.endpoint == nil && (hostEnv == nil || hostEnv?.isEmpty == true)

    guard
      var urlComponents = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false),
      let host = urlComponents.host,
      !host.isEmpty
    else {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(
          isADCFallback: isADCFallback,
          endpoint: baseEndpoint,
          resource: "the universe domain"
        ),
        underlyingError: CredentialsError.parseError(
          "Invalid metadata server endpoint URL: '\(baseEndpoint.absoluteString)'")
      )
    }
    urlComponents.path = "/computeMetadata/v1/universe/universe-domain"

    guard let url = urlComponents.url else {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(
          isADCFallback: isADCFallback,
          endpoint: baseEndpoint,
          resource: "the universe domain"
        ),
        underlyingError: CredentialsError.parseError(
          "Invalid metadata server endpoint URL: '\(baseEndpoint.absoluteString)'")
      )
    }

    let headers = ["Metadata-Flavor": "Google"]

    let fetchOperation: @Sendable () async throws -> String = {
      do {
        let (response, responseHeaders) = try await self.client.getStringWithHeaders(
          url: url, headers: headers)
        try Self.verifyMetadataFlavor(responseHeaders)
        let trimmed = Self.trimASCIIWhitespaceAndNewlines(response)
        if trimmed.isEmpty {
          return defaultUniverseDomain
        }
        guard Self.isValidUniverseDomain(trimmed) else {
          throw CredentialsError.parseError("Invalid universe domain returned by metadata server")
        }
        return trimmed
      } catch let error as AuthHTTPError where error.statusCode == 404 {
        return defaultUniverseDomain
      }
    }

    do {
      if isADCFallback {
        return try await fetchOperation()
      } else {
        return try await RetryEngine.retry(
          configuration: self.retryConfiguration ?? .defaultConfiguration,
          isRetryable: AuthHTTPError.isRetryable,
          operation: fetchOperation
        )
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let AuthHTTPError.unknown(inner) where inner is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(
          isADCFallback: isADCFallback,
          endpoint: baseEndpoint,
          resource: "the universe domain"
        ),
        underlyingError: error
      )
    }
  }
}
