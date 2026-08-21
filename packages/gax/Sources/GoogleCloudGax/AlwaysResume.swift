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

/// A ``ResumePolicy`` that attempts to resume on all recoverable errors without imposing limits
/// on consecutive or total attempts.
public struct AlwaysResume: ResumePolicy, Sendable, Equatable {
  public init() {}

  public func onError(state: ResumeState, error: RequestError) -> ResumeResult {
    guard error.isRecoverableForResume else {
      return .permanent(error)
    }
    return .resume(error)
  }
}

extension ResumePolicy where Self == AlwaysResume {
  /// An `AlwaysResume` policy that attempts to resume on all recoverable errors indefinitely.
  public static var always: AlwaysResume {
    AlwaysResume()
  }
}
