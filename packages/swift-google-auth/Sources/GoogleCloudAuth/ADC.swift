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

/// A utility that resolves Application Default Credentials (ADC) according to [AIP-4110](https://google.aip.dev/auth/4110) guidelines.
enum ADC: Sendable {
  private static let isInitialized: Bool = {
    CredentialParserRegistry.shared.register(parser: ServiceAccountParser.self)
    CredentialParserRegistry.shared.register(parser: UserCredentialsParser.self)
    return true
  }()

  /// Resolves the configured credentials source shell.
  ///
  /// - Returns: An empty credentials source skeleton.
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
      return MDSCredentials(quotaProjectID: quotaProject, fromADC: true, environment: environment)
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
