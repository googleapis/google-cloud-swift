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

/// A ``ResumePolicy`` that caps the total number of resume attempts across the entire transfer operation.
public struct LimitedTotalResumes<Details: Sendable>: ResumePolicy, Sendable, Equatable {
  /// The maximum number of total resume attempts allowed across the transfer.
  public let maxTotalResumes: UInt32

  /// Creates a new `LimitedTotalResumes` instance.
  ///
  /// - Parameter maxTotalResumes: The maximum total resume count.
  public init(maxTotalResumes: UInt32 = 10) {
    self.maxTotalResumes = maxTotalResumes
  }

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    guard error.isRecoverableForResume else {
      return .permanent(error)
    }

    if state.totalResumeCount >= maxTotalResumes {
      return .exhausted(error)
    }

    return .resume(error)
  }
}

extension ResumePolicy {
  /// Creates a `LimitedTotalResumes` resume policy with a specified limit.
  public static func limitedTotalResumes<D: Sendable>(_ maxTotalResumes: UInt32)
    -> LimitedTotalResumes<D> where Self == LimitedTotalResumes<D>
  {
    LimitedTotalResumes(maxTotalResumes: maxTotalResumes)
  }
}
