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

/// Configuration options for Service Account Impersonation credentials.
///
/// Under [AIP-4110](https://google.aip.dev/auth/4110), service account impersonation uses a base
/// `sourceCredentials` instance to request short-lived access tokens for `targetPrincipal` via the
/// Google Cloud IAM Service Account Credentials API (`:generateAccessToken`).
///
/// See [Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation).
public struct ImpersonatedServiceAccountConfig: Sendable {
  /// The default scope requested for impersonated service account access tokens.
  public static let defaultScope = "https://www.googleapis.com/auth/cloud-platform"

  /// The base credentials used to authenticate requests to the IAM Credentials API.
  public let sourceCredentials: Credentials

  /// The email address or resource name (`projects/-/serviceAccounts/{email_or_unique_id}`) of the target service account to impersonate.
  public let targetPrincipal: String

  /// Optional ordered sequence of service account email addresses or resource names in a delegation chain.
  ///
  /// Each service account in the chain must be granted `roles/iam.serviceAccountTokenCreator` on the next
  /// service account in the chain, with the final delegate granted token creator access on `targetPrincipal`.
  public var delegates: [String] = []

  /// Scopes requested for the impersonated access token. Defaults to `[defaultScope]`.
  public var scopes: [String] = [defaultScope]

  /// Desired lifetime duration of the impersonated access token (defaults to 3600 seconds / 1 hour).
  public var lifetime: Duration = .seconds(3600)

  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target Google Cloud universe domain override.
  ///
  /// When `nil`, defaults to the universe domain of `sourceCredentials`.
  public var universeDomain: String? = nil

  /// Initializes a new instance of `ImpersonatedServiceAccountConfig`.
  ///
  /// - Parameters:
  ///   - sourceCredentials: The base credentials used to authenticate the impersonation request.
  ///   - targetPrincipal: The email address or resource name of the target service account to impersonate.
  public init(
    sourceCredentials: Credentials,
    targetPrincipal: String
  ) {
    self.sourceCredentials = sourceCredentials
    self.targetPrincipal = targetPrincipal
  }

  /// Configures optional properties of `ImpersonatedServiceAccountConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ImpersonatedServiceAccountConfig) throws -> Void) rethrows
    -> ImpersonatedServiceAccountConfig
  {
    var copy = self
    try configure(&copy)
    return copy
  }
}
