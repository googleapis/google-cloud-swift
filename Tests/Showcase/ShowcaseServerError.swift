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

/// Errors thrown while locating or starting a local `gapic-showcase` server process.
enum ShowcaseServerError: Error, CustomStringConvertible, CustomDebugStringConvertible {
  /// The `GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH` environment variable is unset or does not point to an
  /// executable `gapic-showcase` binary.
  case binaryNotFound

  /// The `gapic-showcase` process exited prematurely or failed to write its CA certificate and
  /// start listening before the startup deadline elapsed.
  case startupTimeout(String)

  var description: String {
    switch self {
    case .binaryNotFound:
      return "gapic-showcase binary not found at GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"
    case .startupTimeout(let detail):
      return "Timed out waiting for gapic-showcase startup: \(detail)"
    }
  }

  var debugDescription: String {
    switch self {
    case .binaryNotFound:
      return "ShowcaseServerError.binaryNotFound: \(self.description)"
    case .startupTimeout:
      return "ShowcaseServerError.startupTimeout: \(self.description)"
    }
  }
}
