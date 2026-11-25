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

@_spi(GoogleCloudInternal) import GoogleAuth

/// Dependency injection for `_HTTPClient`.
///
/// Allow testing `_HTTPClient` with mock credentials.
protocol CredentialsProtocol: Sendable {
  func headers() async throws -> GoogleAuth.AuthHeaders
  func _universeDomain() async throws -> _UniverseDomain
  func _validateUniverseDomain(_ expectedUniverseDomain: _UniverseDomain) async throws
}

extension CredentialsProtocol {
  func _universeDomain() async throws -> _UniverseDomain {
    .default
  }

  func _validateUniverseDomain(_ expectedUniverseDomain: _UniverseDomain) async throws {
    let credUniverse = try await self._universeDomain()
    guard credUniverse == expectedUniverseDomain else {
      throw CredentialsError.parseError(
        "The configured universe domain (\(expectedUniverseDomain)) does not match the universe domain found in the credentials (\(credUniverse)). If you haven't configured the universe domain explicitly, `googleapis.com` is the default."
      )
    }
  }
}

extension GoogleAuth.Credentials: CredentialsProtocol {}
