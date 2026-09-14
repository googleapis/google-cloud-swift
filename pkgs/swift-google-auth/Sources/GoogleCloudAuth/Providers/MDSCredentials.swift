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

/// Credentials backed by the Google Cloud Metadata Service (MDS).
///
/// In Google Cloud environments such as [Google Compute Engine (GCE)](https://cloud.google.com/compute),
/// [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine), or
/// [Cloud Run](https://cloud.google.com/run), workloads run with an attached
/// [default service account](https://cloud.google.com/iam/docs/service-account-types#default).
/// The Compute Engine Metadata Service is a link-local HTTP server accessible from within the
/// instance at `http://metadata.google.internal` (or `169.254.169.254`).
///
/// ### Security and Keyless Authentication
/// Unlike service account key files (`service_account`), MDS credentials do not require downloading,
/// storing, or rotating private RSA keys on the host. Instead, the runtime environment requests
/// short-lived OAuth 2.0 access tokens directly from the metadata server. To protect against
/// Server-Side Request Forgery (SSRF), all metadata requests require the HTTP header:
/// ```http
/// Metadata-Flavor: Google
/// ```
///
/// ### Environment Variable Override
/// The default hostname `metadata.google.internal` can be overridden by setting the
/// `GCE_METADATA_HOST` environment variable, which is useful during local testing or emulation.
///
/// - SeeAlso: [Google Cloud Metadata Server Documentation](https://cloud.google.com/compute/docs/metadata/overview)
/// - SeeAlso: [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials)
struct MDSCredentials: CredentialsProvider, Sendable {
  /// The underlying token provider responsible for querying the metadata server endpoint.
  let provider: MDSAccessTokenProvider

  /// The token cache handling proactive refresh and jittered expiration management.
  let cache: TokenCache<ContinuousClock>

  /// An optional Google Cloud project ID to attribute quota and billing to.
  var quotaProjectID: String? { provider.quotaProjectID }

  /// Initializes a new instance of `MDSCredentials`.
  ///
  /// - Parameters:
  ///   - endpoint: An optional custom URL override for the metadata server. When `nil`,
  ///     the provider checks `GCE_METADATA_HOST` or defaults to `http://metadata.google.internal`.
  ///   - quotaProjectID: An optional Google Cloud project ID for quota and billing attribution.
  ///   - scopes: An optional array of OAuth 2.0 scopes requested for the minted access tokens.
  ///   - retryConfiguration: Optional retry policy configuration for metadata server HTTP calls.
  ///   - client: The HTTP client used to execute requests against the metadata server.
  ///   - fromADC: A boolean indicating whether these credentials were created as part of the
  ///     Application Default Credentials (ADC) discovery cascade.
  ///   - environment: The environment dictionary containing system environment variables.
  ///   - jitter: Optional jitter generator for scheduling token refresh in `TokenCache`.
  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    scopes: [String]? = nil,
    retryConfiguration: RetryConfiguration? = nil,
    client: AuthHTTPClient = AuthHTTPClient(),
    fromADC: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    jitter: TokenCache<ContinuousClock>.JitterGenerator? = TokenCache<ContinuousClock>.defaultJitter
  ) {
    let provider = MDSAccessTokenProvider(
      endpoint: endpoint,
      quotaProjectID: quotaProjectID,
      scopes: scopes,
      retryConfiguration: retryConfiguration,
      client: client,
      fromADC: fromADC,
      environment: environment
    )
    self.provider = provider

    self.cache = TokenCache(
      provider: provider,
      jitter: jitter,
      isRetryable: MDSAccessTokenProvider.isRetryable
    )
  }

  // MARK: - CredentialsProvider

  /// Returns authorization headers containing a fresh access token obtained from the metadata server.
  ///
  /// Includes `Authorization: Bearer <token>` and, if configured, `x-goog-user-project: <quotaProjectID>`.
  ///
  /// - Returns: An array of key-value header pairs.
  /// - Throws: `CredentialsError.cannotFetchToken` if the metadata server cannot be reached or returns an error.
  func headers() async throws -> [(String, String)] {
    let token = try await self.cache.token()
    var headers = [("Authorization", "Bearer \(token.accessToken)")]
    if let quota = self.provider.quotaProjectID {
      headers.append(("x-goog-user-project", quota))
    }
    return headers
  }

  /// Retrieves the universe domain string override.
  ///
  /// For MDS credentials in the default Google Cloud [universe](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones),
  /// returns `nil` to indicate the standard `googleapis.com` domain.
  ///
  /// - Returns: Always `nil` for default MDS credentials.
  func universeDomain() async -> String? {
    return nil
  }
}
