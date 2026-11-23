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
  /// Transient or unclassified failure: eligible for `RetryEngine`, `TokenCache` background retry,
  /// and transport-level retry/resume (`CredentialsError._isRetryable == true`), and never latched
  /// as `permanentError`.
  case retryable

  /// Definitively permanent failure: fails immediately (`_isRetryable == false`) and latches
  /// `permanentError` in `TokenCache` / `MDSUniverseDomainCache`.
  case permanent

  /// Non-retryable failure that must not be latched across future calls (such as task
  /// cancellation or an unconfirmed implicit ADC metadata server probe): fails the current request
  /// fast (`_isRetryable == false`) without background polling or latching `permanentError`.
  case uncached
}

/// Internal protocol adopted by error types to declare their authentication retry and caching
/// disposition without cross-type downcasting.
protocol ClassifiedAuthError: Error {
  var errorDisposition: TokenErrorDisposition { get }
}

extension URLError: ClassifiedAuthError {
  /// Classifies `URLError` codes in favor of retrying unless the code represents cancellation or a
  /// local URL/file configuration failure that cannot recover on retry.
  var errorDisposition: TokenErrorDisposition {
    switch self.code {
    case .cancelled:
      return .uncached
    case .badURL,
      .unsupportedURL,
      .fileDoesNotExist,
      .noPermissionsToReadFile:
      return .permanent
    default:
      return .retryable
    }
  }
}

extension TokenErrorDisposition {
  /// Resolves the `TokenErrorDisposition` for an arbitrary `any Error`.
  ///
  /// Checks `as? URLError` explicitly in addition to `as? any ClassifiedAuthError` because on
  /// Darwin, boxing `URLError` into `any Error` bridges it to `NSError` (`NSURLErrorDomain`),
  /// which does not match a protocol existential cast without a concrete `_ObjectiveCBridgeableError`
  /// cast.
  static func classify(_ error: any Error) -> TokenErrorDisposition {
    if error is CancellationError {
      return .uncached
    }
    if let classified = error as? any ClassifiedAuthError {
      return classified.errorDisposition
    }
    if let urlError = error as? URLError {
      return urlError.errorDisposition
    }
    return .retryable
  }
}
