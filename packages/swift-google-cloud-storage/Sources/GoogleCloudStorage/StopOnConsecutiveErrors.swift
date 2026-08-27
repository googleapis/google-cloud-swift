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

/// A ``ResumePolicy`` decorator that permits resumes as long as forward progress
/// is made, halting when consecutive errors reach a maximum threshold.
public struct StopOnConsecutiveErrors<P: Sendable>: Sendable {
  /// The inner resume policy being decorated.
  public let inner: P

  /// The maximum number of consecutive errors permitted before the transfer is abandoned.
  public let maxConsecutiveErrors: UInt32

  /// Creates a new `StopOnConsecutiveErrors` instance.
  ///
  /// - Parameters:
  ///   - inner: The underlying resume policy.
  ///   - maxConsecutiveErrors: The maximum number of consecutive errors without forward progress. Defaults to 3.
  public init(inner: P, maxConsecutiveErrors: UInt32 = 3) {
    self.inner = inner
    self.maxConsecutiveErrors = maxConsecutiveErrors
  }
}

extension StopOnConsecutiveErrors: ResumePolicy where P: ResumePolicy & Sendable {
  public typealias Details = P.Details

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    switch inner.onError(state: state, error: error) {
    case .permanent(let e):
      return .permanent(e)
    case .exhausted(let e):
      return .exhausted(e)
    case .resume(let e):
      if state.consecutiveErrorCount >= maxConsecutiveErrors {
        return .exhausted(e)
      }
      return .resume(e)
    }
  }

  public func onProgress(state: inout ResumeState<Details>) {
    inner.onProgress(state: &state)
  }

  public func remainingTime(state: ResumeState<Details>) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension StopOnConsecutiveErrors: Equatable where P: Equatable {}

extension ResumePolicy {
  /// Decorates a `ResumePolicy` to halt when consecutive errors exceed a threshold without forward progress.
  ///
  /// - Parameter maxConsecutiveErrors: The maximum consecutive error threshold. Defaults to 3.
  /// - Returns: A decorated resume policy.
  public func stopOnConsecutiveErrors(_ maxConsecutiveErrors: UInt32 = 3)
    -> StopOnConsecutiveErrors<Self>
  {
    StopOnConsecutiveErrors(inner: self, maxConsecutiveErrors: maxConsecutiveErrors)
  }
}
