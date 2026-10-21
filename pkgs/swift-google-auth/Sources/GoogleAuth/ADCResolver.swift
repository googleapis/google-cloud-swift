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

package import Foundation
import SystemPackage

/// The outcome of loading Application Default Credentials (ADC) from the local filesystem.
package enum ADCContents: Equatable, Sendable {
  /// The raw file content data loaded from disk.
  case contents(Data)
  /// No credential file was found in standard locations, signaling fallback to the Metadata Server (MDS).
  case fallbackToMds
}

/// Loads the Application Default Credentials file content if available, or signals fallback to the Metadata Server.
///
/// Follows the error semantics defined for [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials):
/// - If `GOOGLE_APPLICATION_CREDENTIALS` is set but points to a non-existent or unreadable file,
///   throws `CredentialsError.cannotLoadFile(message:underlyingError:)` immediately rather than falling back.
/// - If the well-known file location does not exist, returns `.fallbackToMds`.
///
/// - Parameter environment: The environment dictionary to inspect.
/// - Returns: An `ADCContents` value containing either raw file data or a fallback signal.
/// - Throws: A `CredentialsError.cannotLoadFile` if an environment-specified file cannot be found or read.
package func loadADC(
  environment: [String: String] = ProcessInfo.processInfo.environment
) throws -> ADCContents {
  guard let pathInfo = resolveADCPath(environment: environment) else {
    return .fallbackToMds
  }

  let filePath: FilePath
  let isEnvironmentOverride: Bool
  switch pathInfo {
  case .environmentVariable(let p):
    filePath = p
    isEnvironmentOverride = true
  case .wellKnown(let p):
    filePath = p
    isEnvironmentOverride = false
  }

  do {
    // FilePath string representation is OS-native
    let data = try Data(contentsOf: URL(fileURLWithPath: filePath.string))
    return .contents(data)
  } catch {
    if isEnvironmentOverride {
      throw CredentialsError.cannotLoadFile(
        message:
          "Could not load credentials file at '\(filePath.string)' specified by GOOGLE_APPLICATION_CREDENTIALS",
        underlyingError: error
      )
    } else {
      return .fallbackToMds
    }
  }
}
