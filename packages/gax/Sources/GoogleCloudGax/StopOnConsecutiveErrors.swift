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

/// A ``ResumePolicy`` that permits indefinite resumes across a transfer as long as forward progress
/// is made, halting only when consecutive errors occur without advancing any bytes.
///
/// This is the recommended default policy for resumable transfers like Cloud Storage uploads and downloads.
public struct StopOnConsecutiveErrors: ResumePolicy, Sendable, Equatable {
  /// The maximum number of consecutive errors permitted before the transfer is abandoned.
  public let maxConsecutiveErrors: UInt32

  /// Creates a new `StopOnConsecutiveErrors` instance.
  ///
  /// - Parameter maxConsecutiveErrors: The maximum number of consecutive errors without forward progress. Defaults to 3.
  public init(maxConsecutiveErrors: UInt32 = 3) {
    self.maxConsecutiveErrors = maxConsecutiveErrors
  }

  public func onError(state: ResumeState, error: RequestError) -> ResumeResult {
    guard error.isRecoverableForResume else {
      return .permanent(error)
    }

    if state.consecutiveErrorCount >= maxConsecutiveErrors {
      return .exhausted(error)
    }

    return .resume(error)
  }
}

extension ResumePolicy where Self == StopOnConsecutiveErrors {
  /// A `StopOnConsecutiveErrors` resume policy with default settings (max 3 consecutive errors).
  public static var stopOnConsecutiveErrors: StopOnConsecutiveErrors {
    StopOnConsecutiveErrors()
  }

  /// Creates a `StopOnConsecutiveErrors` resume policy with a custom consecutive error threshold.
  public static func stopOnConsecutiveErrors(maxConsecutiveErrors: UInt32)
    -> StopOnConsecutiveErrors
  {
    StopOnConsecutiveErrors(maxConsecutiveErrors: maxConsecutiveErrors)
  }
}
