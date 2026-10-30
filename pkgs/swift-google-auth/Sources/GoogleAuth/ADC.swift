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
  /// Minimal header decoded from a credential JSON payload to identify its `"type"`
  /// (e.g., `"service_account"` or `"authorized_user"`) before delegating the raw `Data`
  /// to the matching `CredentialSourceParser` for full `Decodable` parsing.
  private struct CredentialHeader: Decodable {
    let type: String
  }

  private static let isInitialized: Bool = {
    CredentialParserRegistry.shared.register(parser: ServiceAccountParser.self)
    CredentialParserRegistry.shared.register(parser: UserCredentialsParser.self)
    CredentialParserRegistry.shared.register(parser: ImpersonatedServiceAccountParser.self)
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
  /// - Throws: A `CredentialsError` if loading or parsing fails, or if an unsupported credential type is encountered.
  static func resolve(
    quotaProjectID: String? = nil,
    universeDomain: String? = nil,
    scopes: [String] = [],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> any CredentialsProvider {
    _ = isInitialized
    let quotaProject = environment["GOOGLE_CLOUD_QUOTA_PROJECT"] ?? quotaProjectID
    let resolvedUniverseDomain = nonEmpty(universeDomain)

    let contents = try loadADC(environment: environment)
    switch contents {
    case .fallbackToMds:
      return MDSCredentials(
        quotaProjectID: quotaProject,
        universeDomain: resolvedUniverseDomain,
        scopes: scopes,
        fromADC: true,
        environment: environment
      )
    case .contents(let data):
      // Decode only the top-level `"type"` discriminator first so the original JSON `Data`
      // can be passed directly to the registered parser without an intermediate
      // `[String: Any]` dictionary roundtrip.
      let header: CredentialHeader
      do {
        header = try JSONDecoder().decode(CredentialHeader.self, from: data)
      } catch {
        throw CredentialsError.parseError(
          "Failed to parse Application Default Credentials JSON: \(error)")
      }

      if let source = try CredentialParserRegistry.shared.parse(
        type: header.type,
        data: data,
        quotaProjectID: quotaProject,
        universeDomain: resolvedUniverseDomain,
        scopes: scopes,
        environment: environment
      ) {
        return source
      }
      throw CredentialsError.notSupported(
        "Unsupported Application Default Credentials type: \(header.type)")
    }
  }
}
