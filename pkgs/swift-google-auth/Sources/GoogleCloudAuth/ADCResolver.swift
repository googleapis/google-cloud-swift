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

package enum ADCContents: Equatable, Sendable {
  case contents(Data)
  case fallbackToMds
}

package enum ADCResolverError: Error, Equatable {
  case fileNotFound(path: String, isEnvironmentOverride: Bool)
  case invalidFormat
  case unsupportedType(String)
}

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
      throw ADCResolverError.fileNotFound(path: filePath.string, isEnvironmentOverride: true)
    } else {
      return .fallbackToMds
    }
  }
}
