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

/// A ``ResumePolicy`` that attempts to resume on all errors without imposing limits
/// on consecutive or total attempts.
///
/// Use ``unbounded()`` decorated with ``StopOnConsecutiveErrors`` and/or
/// ``LimitedTotalResumes`` to configure bounds. For standard default Cloud Storage
/// resume behavior, use ``StorageResumePolicy/defaultPolicy``.
///
/// The policy resumes on all errors regardless of idempotency. This is primarily useful in
/// testing or specialized custom recovery pipelines.
public struct AlwaysResume<Details: Sendable>: ResumePolicy, Sendable, Equatable {
  init() {}

  /// Creates an unconstrained resume policy that attempts to resume on all errors indefinitely.
  ///
  /// Decorate this policy with ``StopOnConsecutiveErrors`` and/or
  /// ``LimitedTotalResumes`` to bound the resume loop:
  /// ```swift
  /// let policy = AlwaysResume<WriteObjectDetails>.unbounded()
  ///   .stopOnConsecutiveErrors(3)
  ///   .withTotalResumeLimit(10)
  /// ```
  ///
  /// - Warning: Without `.stopOnConsecutiveErrors(_:)` or `.withTotalResumeLimit(_:)` decorators,
  ///   this policy resumes errors indefinitely.
  public static func unbounded() -> AlwaysResume<Details> {
    AlwaysResume()
  }

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    .resume(error)
  }
}
