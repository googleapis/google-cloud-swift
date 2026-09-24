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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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

  /// An optional list of OAuth 2.0 scopes requested for the token.
  let scopes: [String]?

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
  ///   - scopes: Optional OAuth 2.0 scopes requested for the token.
  ///   - retryConfiguration: Retry policy configuration for network requests.
  ///   - client: HTTP client instance.
  ///   - fromADC: Set to `true` if instantiated during ADC resolution.
  ///   - environment: Process environment dictionary.
  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    scopes: [String]? = nil,
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

  /// Determines whether an HTTP or network error encountered while contacting the metadata server is retryable.
  ///
  /// - Parameter error: The error to evaluate.
  /// - Returns: `true` for HTTP 5xx, 429, 408, or network-level errors; `false` for 4xx client errors.
  static func isRetryable(_ error: Error) -> Bool {
    if let authError = error as? AuthHTTPError, let status = authError.statusCode {
      return status >= 500 || status == 429 || status == 408
    }
    return true
  }

  /// Resolves the metadata server base URL.
  ///
  /// Precedence: the explicit `endpoint`, then `GCE_METADATA_HOST`, then `defaultEndpoint`.
  ///
  /// - Parameter hostEnv: The value of `GCE_METADATA_HOST`, if set.
  /// - Returns: The base URL to use for metadata server requests.
  private func resolveBaseEndpoint(hostEnv: String?) -> URL {
    if let endpoint = self.endpoint {
      return endpoint
    }
    if let hostEnv = hostEnv, !hostEnv.isEmpty {
      let hostString = hostEnv.hasPrefix("http") ? hostEnv : "http://\(hostEnv)"
      return URL(string: hostString)!
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
    let baseEndpoint = self.resolveBaseEndpoint(hostEnv: hostEnv)

    var urlComponents = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)!
    urlComponents.path = "/computeMetadata/v1/instance/service-accounts/default/token"

    if let scopes = self.scopes, !scopes.isEmpty {
      urlComponents.queryItems = [
        URLQueryItem(name: "scopes", value: scopes.joined(separator: ","))
      ]
    }

    guard let url = urlComponents.url else {
      throw URLError(.badURL)
    }

    let headers = ["Metadata-Flavor": "Google"]

    struct TokenResponse: Decodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }

    let fetchOperation: @Sendable () async throws -> Token = {
      let response: TokenResponse = try await self.client.get(url: url, headers: headers)
      let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
      return Token(accessToken: response.accessToken, expirationDate: expiration)
    }

    // ADC falls back to the metadata server when it finds no other credentials. Outside Google
    // Cloud that fallback cannot succeed, so fail fast instead of retrying.
    let isADCFallback = self.fromADC && hostEnv == nil

    do {
      if isADCFallback {
        return try await fetchOperation()
      } else {
        return try await RetryEngine.retry(
          configuration: self.retryConfiguration ?? .defaultConfiguration,
          isRetryable: Self.isRetryable,
          operation: fetchOperation
        )
      }
    } catch {
      throw CredentialsError.cannotFetchToken(
        message: Self.errorMessage(isADCFallback: isADCFallback, endpoint: baseEndpoint),
        source: error
      )
    }
  }
}
