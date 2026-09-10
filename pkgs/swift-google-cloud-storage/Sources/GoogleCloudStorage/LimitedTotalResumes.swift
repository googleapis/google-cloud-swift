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

/// A ``ResumePolicy`` decorator that caps the total number of resume attempts across an entire operation.
public struct LimitedTotalResumes<P: Sendable>: Sendable {
  /// The inner resume policy being decorated.
  public let inner: P

  /// The maximum number of total resume attempts allowed across the transfer.
  public let maxTotalResumes: UInt32

  /// Creates a new `LimitedTotalResumes` instance.
  ///
  /// - Parameters:
  ///   - inner: The underlying resume policy.
  ///   - maxTotalResumes: The maximum total resume count. Defaults to 10.
  public init(inner: P, maxTotalResumes: UInt32 = 10) {
    self.inner = inner
    self.maxTotalResumes = maxTotalResumes
  }
}

extension LimitedTotalResumes: ResumePolicy where P: ResumePolicy & Sendable {
  public typealias Details = P.Details

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    switch inner.onError(state: state, error: error) {
    case .permanent(let e):
      return .permanent(e)
    case .exhausted(let e):
      return .exhausted(e)
    case .resume(let e):
      if state.totalResumeCount >= maxTotalResumes {
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

extension LimitedTotalResumes: Equatable where P: Equatable {}

extension ResumePolicy {
  /// Decorates a `ResumePolicy` to limit total resume attempts.
  ///
  /// - Parameter maxTotalResumes: The maximum total resume count allowed. Defaults to 10.
  /// - Returns: A decorated resume policy.
  public func withTotalResumeLimit(_ maxTotalResumes: UInt32 = 10) -> LimitedTotalResumes<Self> {
    LimitedTotalResumes(inner: self, maxTotalResumes: maxTotalResumes)
  }
}
