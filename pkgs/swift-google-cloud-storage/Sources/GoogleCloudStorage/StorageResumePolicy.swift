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
public import GoogleGax
import GoogleRpc

/// Evaluates whether an error is considered resumable in Google Cloud Storage.
///
/// In Google Cloud Storage, idempotent data transfers (most uploads and downloads) can be resumed
/// on I/O errors, transient HTTP status codes (408, 429, and 5xx), and transient
/// gRPC/service status codes (`unavailable`, `resourceExhausted`, `deadlineExceeded`, `internal`).
///
/// If the transfer operation is not idempotent (some single-shot uploads), errors are treated
/// as permanent and will not be resumed or retried.
///
/// Use ``defaultPolicy`` for the standard bounded configuration (stopping after 3 consecutive
/// errors without byte progress), or ``unbounded()`` decorated with ``StopOnConsecutiveErrors``
/// or ``LimitedTotalResumes`` to configure custom limits:
/// ```swift
/// let resumePolicy = StorageResumePolicy<WriteObjectDetails>.unbounded()
///   .stopOnConsecutiveErrors(3)
/// ```
public struct StorageResumePolicy<Details: Sendable>: ResumePolicy, Sendable, Equatable {
  init() {}

  /// Creates an unconstrained Cloud Storage resume policy without error or resume count limits.
  ///
  /// - Warning: Without `.stopOnConsecutiveErrors(_:)` or `.withTotalResumeLimit(_:)` decorators,
  ///   this policy resumes transient transfer errors indefinitely.
  public static func unbounded() -> StorageResumePolicy<Details> {
    StorageResumePolicy()
  }

  /// The default resume policy for Google Cloud Storage, stopping after 3 consecutive errors
  /// without byte progress.
  public static var defaultPolicy: some ResumePolicy<Details> {
    StorageResumePolicy<Details>.unbounded().stopOnConsecutiveErrors()
  }

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    guard state.idempotent else {
      return .permanent(error)
    }
    if isResumable(error) {
      return .resume(error)
    }
    return .permanent(error)
  }

  private func isResumable(_ error: RequestError) -> Bool {
    switch error {
    case .io:
      return true
    case .http(let details):
      let code = details.httpStatusCode
      return code == 408 || code == 429 || (500...599).contains(code)
    case .service(let details):
      let code = details.code
      return code == .unavailable || code == .resourceExhausted || code == .deadlineExceeded
        || code == .`internal`
    case .binding, .exhausted, .unimplemented, .malformedResponse, .badURL:
      return false
    @unknown default:
      return false
    }
  }
}
