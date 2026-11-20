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

/// Retry and cache-latching classification for authentication errors.
enum TokenErrorDisposition: Equatable, Sendable {
  /// Transient failure: eligible for `RetryEngine`, `TokenCache` background retry, and
  /// transport-level retry/resume (`CredentialsError._isRetryable == true`).
  case retryable

  /// Definitively permanent failure: fails immediately (`_isRetryable == false`) and latches
  /// `permanentError` in `TokenCache` / `MDSUniverseDomainCache`.
  case permanent

  /// Non-retryable failure whose permanence across future calls is unknown (such as task
  /// cancellation or an opaque custom supplier error): fails the current request fast
  /// (`_isRetryable == false`) without background polling or latching `permanentError`.
  case uncached
}

/// Internal protocol adopted by `GoogleAuth` error types to declare their retry and caching
/// disposition without cross-type downcasting.
protocol ClassifiedAuthError: Error {
  var errorDisposition: TokenErrorDisposition { get }
}

extension URLError {
  /// Whether this error represents a transient TCP, DNS, or connectivity failure.
  ///
  /// Configuration, file-system, authentication, cancellation, and TLS certificate `URLError`
  /// codes (such as `.badURL`, `.fileDoesNotExist`, `.userAuthenticationRequired`,
  /// `.serverCertificateUntrusted`, and `.cancelled`) return `false`.
  var isTransientNetworkError: Bool {
    switch self.code {
    case .timedOut,
      .networkConnectionLost,
      .cannotConnectToHost,
      .notConnectedToInternet,
      .dnsLookupFailed,
      .cannotFindHost:
      return true
    default:
      return false
    }
  }
}
