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
import GoogleCloudGax
import GoogleRpc

/// Evaluates whether an error is considered resumable in Google Cloud Storage.
///
/// In Google Cloud Storage, resumable data transfers (uploads and downloads) can be resumed
/// on I/O errors, transient HTTP status codes (408, 429, 502, 503, 504), and transient
/// gRPC/service status codes (`unavailable`, `resourceExhausted`, `deadlineExceeded`).
///
/// This policy can be composed with decorators such as ``StopOnConsecutiveErrors`` or
/// ``LimitedTotalResumes``:
/// ```swift
/// let resumePolicy = StorageResumePolicy<UploadDetails>().stopOnConsecutiveErrors(3)
/// ```
public struct StorageResumePolicy<Details: Sendable>: ResumePolicy, Sendable, Equatable {
  public init() {}

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
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
      let code = details.http_status_code
      return code == 408 || code == 429 || code == 502 || code == 503 || code == 504
    case .service(let details):
      let code = details.code
      return code == .unavailable || code == .resourceExhausted || code == .deadlineExceeded
    case .binding, .exhausted, .unimplemented, .malformedResponse:
      return false
    @unknown default:
      return false
    }
  }
}
