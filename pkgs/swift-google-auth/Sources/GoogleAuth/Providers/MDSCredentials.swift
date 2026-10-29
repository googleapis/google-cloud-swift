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

/// Thread-safe actor caching the metadata server's universe domain response.
actor MDSUniverseDomainCache {
  private var cached: String?
  private var permanentError: (any Error)?
  private var activeTask: Task<String, any Error>?

  deinit {
    activeTask?.cancel()
  }

  func get(using provider: MDSAccessTokenProvider) async throws -> String {
    if let cached = self.cached {
      return cached
    }
    if let error = self.permanentError {
      throw error
    }
    let task: Task<String, any Error>
    if let existing = self.activeTask {
      task = existing
    } else {
      let newTask = Task {
        try await provider.fetchUniverseDomain()
      }
      self.activeTask = newTask
      task = newTask
    }
    do {
      let value = try await task.value
      if self.activeTask == task {
        self.cached = value
        self.activeTask = nil
      }
      return value
    } catch {
      if self.activeTask == task {
        self.activeTask = nil
        if !(error is CancellationError) && !AuthHTTPError.isRetryable(error) {
          self.permanentError = error
        }
      }
      throw error
    }
  }
}

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

  /// An optional explicit universe domain override. When `nil`, the metadata server is queried.
  private let universeDomainOverride: String?

  /// Lazily populated cache for the metadata server universe domain query.
  private let universeDomainCache = MDSUniverseDomainCache()

  /// An optional Google Cloud project ID to attribute quota and billing to.
  var quotaProjectID: String? { provider.quotaProjectID }

  /// Initializes a new instance of `MDSCredentials`.
  ///
  /// - Parameters:
  ///   - endpoint: An optional custom URL override for the metadata server. When `nil`,
  ///     the provider checks `GCE_METADATA_HOST` or defaults to `http://metadata.google.internal`.
  ///   - quotaProjectID: An optional Google Cloud project ID for quota and billing attribution.
  ///   - universeDomain: An optional explicit universe domain override.
  ///   - scopes: Scopes requested for the minted access tokens.
  ///   - retryConfiguration: Optional retry policy configuration for metadata server HTTP calls.
  ///   - client: The HTTP client used to execute requests against the metadata server.
  ///   - fromADC: A boolean indicating whether these credentials were created as part of the
  ///     Application Default Credentials (ADC) discovery cascade.
  ///   - environment: The environment dictionary containing system environment variables.
  ///   - jitter: Optional jitter generator for scheduling token refresh in `TokenCache`.
  init(
    endpoint: URL? = nil,
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String] = [],
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
    self.universeDomainOverride = universeDomain

    self.cache = TokenCache(
      provider: provider,
      jitter: jitter,
      isRetryable: AuthHTTPError.isRetryable
    )
  }

  // MARK: - CredentialsProvider

  /// Resolves the universe domain for these credentials.
  ///
  /// Returns the explicit `universeDomain` override if one was configured, or queries and caches
  /// `/computeMetadata/v1/universe/universe-domain` on the metadata server.
  func universeDomain() async throws -> String {
    if let override = self.universeDomainOverride {
      return override
    }
    return try await self.universeDomainCache.get(using: self.provider)
  }

  /// Returns authorization headers containing a fresh access token obtained from the metadata server.
  ///
  /// Includes `Authorization: Bearer <token>` and, if configured, `x-goog-user-project: <quotaProjectID>`.
  ///
  /// - Returns: The HTTP header fields to apply to the request.
  /// - Throws: `CredentialsError.cannotFetchToken` if the metadata server cannot be reached or returns an error.
  func headers() async throws -> AuthHeaders {
    let token = try await self.cache.token()
    var headers: AuthHeaders = [("Authorization", "Bearer \(token.accessToken)")]
    if let quota = self.provider.quotaProjectID {
      headers.append(name: "x-goog-user-project", value: quota)
    }
    return headers
  }
}
