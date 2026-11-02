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
import Synchronization

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
  /// Tracks whether the metadata server has been confirmed reachable in the current runtime.
  ///
  /// Shared by reference across copies of `MDSAccessTokenProvider` so both `MDSCredentials` and
  /// `TokenCache` observe confirmation once an initial ADC fallback probe reaches a real MDS.
  private final class ProbeState: Sendable {
    private let confirmed = Mutex(false)

    var isConfirmed: Bool {
      confirmed.withLock { $0 }
    }

    func confirm() {
      confirmed.withLock { $0 = true }
    }
  }

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

  /// Shared probe state tracking whether a real metadata server has responded.
  private let probeState = ProbeState()

  /// The canonical base endpoint URL for the Google Cloud Compute Engine metadata server.
  static let defaultEndpoint = "http://metadata.google.internal"

  /// Short HTTP request timeout used when ADC falls back to probing the default metadata server,
  /// avoiding a 30-second hang on non-GCP networks that silently drop packets to `169.254.169.254`.
  static let adcFallbackTimeout: Duration = .seconds(3)

  /// Whether this provider targets the default metadata server via implicit ADC fallback
  /// (no custom `endpoint` and no non-empty `GCE_METADATA_HOST` override).
  private var isImplicitADCFallback: Bool {
    let hostEnv = self.environment["GCE_METADATA_HOST"]
    return self.fromADC && self.endpoint == nil && (hostEnv == nil || hostEnv?.isEmpty == true)
  }

  /// Whether this provider reached the default metadata server via implicit ADC fallback and has
  /// not yet observed a confirmed metadata server response.
  var isUnconfirmedADCFallback: Bool {
    self.isImplicitADCFallback && !self.probeState.isConfirmed
  }

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
    self.quotaProjectID = quotaProjectID
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
  private func resolveBaseEndpoint(hostEnv: String?) throws -> URL {
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
          message: "Could not fetch an access token from the metadata server.",
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
  private static func errorMessage(isADCFallback: Bool, endpoint: URL) -> String {
    let summary =
      "Could not fetch an access token from the metadata server at \(endpoint.absoluteString)."
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

  /// Evaluates whether an error from `fetchToken()` is transient and eligible for retry.
  ///
  /// While an implicit ADC fallback probe has not yet confirmed that a metadata server is present,
  /// failures are treated as permanent so `RetryEngine` and `TokenCache` neither retry in the
  /// background nor stall subsequent `headers()` calls outside Google Cloud. Once MDS reachability
  /// is confirmed, standard `AuthHTTPError.isRetryable(_:)` semantics apply for token refreshes.
  func isRetryable(_ error: any Error) -> Bool {
    if self.isUnconfirmedADCFallback {
      return false
    }
    return AuthHTTPError.isRetryable(error)
  }

  /// Returns `true` when `error` is an HTTP response carrying the `Metadata-Flavor: Google` header,
  /// confirming that a Google Cloud metadata server responded (for example with a transient 503
  /// during VM or pod startup).
  private static func hasMetadataFlavorGoogle(_ error: any Error) -> Bool {
    guard let headers = (error as? AuthHTTPError)?.headers else {
      return false
    }
    return headers.contains { key, value in
      key.caseInsensitiveCompare("Metadata-Flavor") == .orderedSame
        && value.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Google")
          == .orderedSame
    }
  }

  /// Fetches a fresh OAuth 2.0 access token from the metadata server.
  ///
  /// Resolves the base URL using `endpoint`, `GCE_METADATA_HOST`, or `defaultEndpoint`, Appends the token path
  /// `/computeMetadata/v1/instance/service-accounts/default/token`, and includes the required `Metadata-Flavor: Google` header.
  ///
  /// - Returns: A valid `Token` containing the access token string and expiration date.
  /// - Throws: `CredentialsError.cannotFetchToken` if the metadata server is unreachable or returns an error.
  @concurrent
  func fetchToken() async throws -> Token {
    let hostEnv = self.environment["GCE_METADATA_HOST"]
    let baseEndpoint = try self.resolveBaseEndpoint(hostEnv: hostEnv)

    guard
      var urlComponents = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false),
      let host = urlComponents.host,
      !host.isEmpty
    else {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(
          isADCFallback: self.isUnconfirmedADCFallback, endpoint: baseEndpoint),
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
        message: Self.errorMessage(
          isADCFallback: self.isUnconfirmedADCFallback, endpoint: baseEndpoint),
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

    let fetchOperation: @Sendable () async throws -> Token = {
      let timeout: Duration? = self.isUnconfirmedADCFallback ? Self.adcFallbackTimeout : nil
      do {
        let response: TokenResponse = try await self.client.get(
          url: url, headers: headers, timeout: timeout)
        self.probeState.confirm()
        let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        return Token(accessToken: response.accessToken, expirationDate: expiration)
      } catch {
        if Self.hasMetadataFlavorGoogle(error) {
          self.probeState.confirm()
        }
        throw error
      }
    }

    // ADC falls back to the metadata server when it finds no other credentials. Outside Google
    // Cloud that unconfirmed probe fails fast via `adcFallbackTimeout` and `self.isRetryable`
    // returning `false`; once MDS reachability is confirmed, subsequent refreshes use standard
    // timeouts and retry behavior.
    do {
      return try await RetryEngine.retry(
        configuration: self.retryConfiguration ?? .defaultConfiguration,
        isRetryable: { error in self.isRetryable(error) },
        operation: fetchOperation
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(
          isADCFallback: self.isUnconfirmedADCFallback, endpoint: baseEndpoint),
        underlyingError: error
      )
    }
  }
}
