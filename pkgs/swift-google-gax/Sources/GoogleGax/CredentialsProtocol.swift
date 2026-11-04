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

import GoogleAuth

/// Internal dependency-injection seam for unit-testing `_HTTPClient`.
///
/// `GoogleAuth` intentionally exposes concrete `GoogleAuth.Credentials` rather than a public
/// protocol. Keep this protocol `internal` to `GoogleGax`:
/// - Production code and cross-package `@_spi(GoogleCloudInternal)` callers always pass concrete
///   `GoogleAuth.Credentials` (via `ClientOptions.credentials` or `_HTTPClient`'s SPI initializer).
/// - Unit tests in `GoogleGaxTests` (`@testable import GoogleGax`) conform lightweight mock types
///   to `CredentialsProtocol` and inject them via `_HTTPClient`'s `internal` initializer to test
///   header precedence, universe domain mismatches, token-fetch failures, and task cancellation
///   without network or filesystem I/O.
protocol CredentialsProtocol: Sendable {
  /// Returns the authentication headers to attach to an outgoing HTTP request.
  func headers() async throws -> GoogleAuth.AuthHeaders

  /// Returns the universe domain associated with these credentials.
  func universeDomain() async throws -> String

  /// Verifies that these credentials belong to `expectedUniverseDomain` before attaching headers.
  func validateUniverseDomain(_ expectedUniverseDomain: String) async throws
}

// Default implementations for test mocks in `GoogleGaxTests` that only need to stub `headers()`.
// Note that `GoogleAuth.Credentials` provides its own concrete implementations of both methods
// (including treating `.anonymous` credentials as valid in any universe domain).
extension CredentialsProtocol {
  func universeDomain() async throws -> String {
    GoogleAuth.Credentials.defaultUniverseDomain
  }

  func validateUniverseDomain(_ expectedUniverseDomain: String) async throws {
    let credUniverse = try await self.universeDomain()
    guard credUniverse == expectedUniverseDomain else {
      throw CredentialsError.parseError(
        "The configured universe domain (\(expectedUniverseDomain)) does not match the universe domain found in the credentials (\(credUniverse))."
      )
    }
  }
}

extension GoogleAuth.Credentials: CredentialsProtocol {}
