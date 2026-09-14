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
import SystemPackage

/// Represents the location of an Application Default Credentials (ADC) file.
package enum ADCPath: Equatable, Sendable {
  /// The path specified explicitly by the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.
  case environmentVariable(FilePath)
  /// The well-known file location managed by `gcloud auth application-default login`.
  case wellKnown(FilePath)
}

/// Resolves the candidate ADC file path based on environment variables and platform conventions.
///
/// Follows the discovery order defined for [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials):
/// 1. If `GOOGLE_APPLICATION_CREDENTIALS` is present in `environment`, returns `.environmentVariable`.
/// 2. Otherwise, returns `.wellKnown` if the platform-specific well-known directory can be resolved.
///
/// - Parameter environment: The environment variable dictionary to inspect.
/// - Returns: An `ADCPath` if a path is resolved, or `nil` if no candidate file path is available.
package func resolveADCPath(
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> ADCPath? {
  if let envCreds = environment["GOOGLE_APPLICATION_CREDENTIALS"] {
    return .environmentVariable(FilePath(envCreds))
  }

  #if os(Windows)
    if let wellKnown = resolveWellKnownADCPathWindows(environment: environment) {
      return .wellKnown(wellKnown)
    }
  #else
    if let wellKnown = resolveWellKnownADCPathPOSIX(environment: environment) {
      return .wellKnown(wellKnown)
    }
  #endif

  return nil
}

/// Resolves the well-known ADC file path on Windows according to [AIP-4113](https://google.aip.dev/auth/4113).
///
/// Expected path: `%APPDATA%\gcloud\application_default_credentials.json`.
///
/// - Parameter environment: The environment variable dictionary containing `%APPDATA%`.
/// - Returns: The resolved `FilePath`, or `nil` if `APPDATA` is not set.
package func resolveWellKnownADCPathWindows(
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> FilePath? {
  guard let appData = environment["APPDATA"] else {
    return nil
  }
  var path = FilePath(appData)
  path.append("gcloud")
  path.append("application_default_credentials.json")
  return path
}

/// Resolves the well-known ADC file path on POSIX platforms according to [AIP-4110](https://google.aip.dev/auth/4110) and [AIP-4113](https://google.aip.dev/auth/4113).
///
/// Expected path: `$HOME/.config/gcloud/application_default_credentials.json`.
///
/// - Parameter environment: The environment variable dictionary containing `$HOME`.
/// - Returns: The resolved `FilePath`, or `nil` if `HOME` is not set.
package func resolveWellKnownADCPathPOSIX(
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> FilePath? {
  guard let home = environment["HOME"] else {
    return nil
  }
  var path = FilePath(home)
  path.append(".config")
  path.append("gcloud")
  path.append("application_default_credentials.json")
  return path
}
