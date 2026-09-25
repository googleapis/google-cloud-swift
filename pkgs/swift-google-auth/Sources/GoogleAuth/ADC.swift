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

/// An internal utility that resolves Application Default Credentials (ADC).
enum ADC: Sendable {
  private static let isInitialized: Bool = {
    CredentialParserRegistry.shared.register(parser: ServiceAccountParser.self)
    CredentialParserRegistry.shared.register(parser: UserCredentialsParser.self)
    return true
  }()

  /// Resolves and initializes a concrete `CredentialsProvider` matching the environment's ADC configuration.
  ///
  /// Following [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials), this method executes the following discovery steps:
  /// 1. Inspects the `GOOGLE_APPLICATION_CREDENTIALS` environment variable. If defined, attempts to read and parse the referenced file.
  /// 2. Inspects the well-known user credentials file (created via `gcloud auth application-default login`).
  /// 3. Falls back to the link-local [Metadata Server](https://cloud.google.com/compute/docs/metadata/overview) (MDS)
  ///    found in Google Cloud runtime environments (GCE, GKE, Cloud Run).
  ///
  /// **Quota Project Precedence**: If the `GOOGLE_CLOUD_QUOTA_PROJECT` environment variable is set in `environment`,
  /// its value takes precedence over any passed `quotaProjectID`.
  ///
  /// - Parameters:
  ///   - quotaProjectID: An optional project ID used for billing and quota attribution (`x-goog-user-project`).
  ///   - universeDomain: An optional target universe domain (defaults to `googleapis.com`).
  ///   - scopes: Scopes requested for the issued token.
  ///   - environment: The environment variable dictionary used for discovery (defaults to `ProcessInfo.processInfo.environment`).
  /// - Returns: A configured `CredentialsProvider` ready to furnish authentication headers.
  /// - Throws: An `ADCResolverError` or `CredentialsError` if loading or parsing fails, or if an unsupported credential type is encountered.
  static func resolve(
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String] = [],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> any CredentialsProvider {
    _ = isInitialized
    let quotaProject = environment["GOOGLE_CLOUD_QUOTA_PROJECT"] ?? quotaProjectID

    let contents = try loadADC(environment: environment)
    switch contents {
    case .fallbackToMds:
      return MDSCredentials(
        quotaProjectID: quotaProject,
        scopes: scopes,
        fromADC: true,
        environment: environment
      )
    case .contents(let data):
      guard
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
        let type = json["type"] as? String
      else {
        throw ADCResolverError.invalidFormat
      }

      if let source = try CredentialParserRegistry.shared.parse(
        type: type,
        config: json,
        quotaProjectID: quotaProject,
        universeDomain: universeDomain,
        scopes: scopes,
        environment: environment
      ) {
        return source
      }
      throw ADCResolverError.unsupportedType(type)
    }
  }
}
