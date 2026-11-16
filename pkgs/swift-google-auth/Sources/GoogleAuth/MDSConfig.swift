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

/// Configuration options for Google Cloud Metadata Server (MDS) credentials.
///
/// Under [AIP-4115](https://google.aip.dev/auth/4115), MDS credentials fetch short-lived access tokens
/// for a compute runtime's attached service account from the link-local metadata server
/// (`http://metadata.google.internal`).
///
/// See [Metadata Server Overview](https://cloud.google.com/compute/docs/metadata/overview).
public struct MDSConfig: Sendable {
  /// Optional Google Cloud project ID used for billing and quota attribution (`x-goog-user-project`).
  public var quotaProjectID: String? = nil

  /// Optional target [Google Cloud universe domain](https://docs.cloud.google.com/docs/overview#universes_regions_and_zones) override.
  ///
  /// When `nil`, the universe domain is queried lazily from `/computeMetadata/v1/universe/universe-domain`
  /// on the metadata server.
  public var universeDomain: String? = nil

  /// Scopes requested for the minted access token.
  ///
  /// When empty, the metadata server issues a token with all scopes configured for the attached
  /// service account.
  public var scopes: [String] = []

  /// Initializes a new instance of `MDSConfig` without any overrides.
  public init() {}

  /// Configures optional properties of `MDSConfig` using a fluent closure.
  @inlinable
  public func with(_ configure: (inout MDSConfig) throws -> Void) rethrows -> MDSConfig {
    var copy = self
    try configure(&copy)
    return copy
  }
}
