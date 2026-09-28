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
public import struct GoogleAuth.AuthHeaders

/// Common Google header names used across HTTP and gRPC transports.
@_spi(GoogleCloudInternal)
public enum _HeaderNames {
  public static let apiClient = "x-goog-api-client"
  public static let requestParams = "x-goog-request-params"
  public static let userProject = "x-goog-user-project"
  public static let host = "Host"
  public static let authorization = "authorization"
  public static let apiKey = "x-goog-api-key"
  public static let userAgent = "user-agent"

  /// Reserved system and authentication headers that cannot be set or overridden
  /// via `RequestOptions.headers`.
  public static let reservedCustomHeaders: Set<String> = [
    apiClient,
    requestParams,
    userProject,
    host.lowercased(),
    authorization,
    apiKey,
    userAgent,
  ]
}

/// Sanitizes custom headers by stripping reserved system/auth headers and any header
/// provided by `authHeaders`.
@_spi(GoogleCloudInternal)
public func _sanitizeCustomHeaders(
  _ headers: [String: String],
  excluding authHeaders: GoogleAuth.AuthHeaders? = nil
) -> [String: String] {
  headers.filter { key, _ in
    let lower = key.lowercased()
    if _HeaderNames.reservedCustomHeaders.contains(lower) {
      return false
    }
    if let authHeaders, authHeaders.contains(name: key) {
      return false
    }
    return true
  }
}
