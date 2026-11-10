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

/// Configuration options for Application Default Credentials (ADC).
///
/// Under [AIP-4110](https://google.aip.dev/auth/4110), ADC automatically discovers credentials from
/// `GOOGLE_APPLICATION_CREDENTIALS`, well-known `gcloud` user credentials files, or the link-local
/// Compute Engine Metadata Server (MDS).
///
/// ### Usage Example
/// ```swift
/// let config = ADCConfig().with {
///   $0.quotaProjectID = "my-billing-project"
///   $0.scopes = ["https://www.googleapis.com/auth/cloud-platform"]
/// }
/// let credentials = try Credentials(configuration: .adc(config))
/// ```
///
/// See [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials).
public struct ADCConfig: Sendable {
  /// Optional Google Cloud project ID to bill and charge quota against (`x-goog-user-project`).
  ///
  /// Requires `serviceusage.services.use` permission on the project.
  ///
  /// **Important Precedence**: If the `GOOGLE_CLOUD_QUOTA_PROJECT` environment variable is set,
  /// its value takes precedence over this property.
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override (defaults to `googleapis.com`).
  ///
  /// Override this if your application is operating in a custom sovereign or air-gapped cloud.
  public var universeDomain: String? = nil

  /// Scopes requested for the access token, further restricting what the token can be used for.
  public var scopes: [String] = []

  /// Initializes a new instance of `ADCConfig` without any overrides.
  public init() {}

  /// Configures optional properties of `ADCConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout ADCConfig) throws -> Void) rethrows -> ADCConfig {
    var copy = self
    try configure(&copy)
    return copy
  }
}
