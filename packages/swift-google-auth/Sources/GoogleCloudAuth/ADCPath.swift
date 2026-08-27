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

package enum ADCPath: Equatable, Sendable {
  case environmentVariable(FilePath)
  case wellKnown(FilePath)
}

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
