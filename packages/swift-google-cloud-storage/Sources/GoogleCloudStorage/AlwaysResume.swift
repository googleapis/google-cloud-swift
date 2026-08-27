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

/// A ``ResumePolicy`` that attempts to resume on all errors without imposing limits
/// on consecutive or total attempts.
///
/// This policy must be decorated to limit the number of consecutive errors, total resume attempts,
/// or duration of the resume loop.
public struct AlwaysResume<Details: Sendable>: ResumePolicy, Sendable, Equatable {
  public init() {}

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    .resume(error)
  }
}

extension ResumePolicy {
  /// An `AlwaysResume` policy that attempts to resume on all errors indefinitely.
  public static func always<D: Sendable>() -> AlwaysResume<D> where Self == AlwaysResume<D> {
    AlwaysResume<D>()
  }
}
