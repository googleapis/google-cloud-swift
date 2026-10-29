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

public import GoogleGax

/// A ``ResumePolicy`` decorator that caps the total number of resume attempts across an entire operation.
///
/// The decorator passes through ``ResumeResult/permanent(_:)`` and ``ResumeResult/exhausted(_:)``
/// decisions from the inner policy unchanged, and replaces ``ResumeResult/resume(_:)`` with
/// ``ResumeResult/exhausted(_:)`` once ``ResumeState/totalResumeCount`` reaches the configured
/// limit, regardless of whether forward progress has been made. Because the resume loop increments
/// ``ResumeState/totalResumeCount`` before consulting ``onError(state:error:)``, setting the limit
/// to `0` or `1` halts on the first error without resuming.
///
/// Construct this decorator using ``ResumePolicy/withTotalResumeLimit(_:)``.
public struct LimitedTotalResumes<P: ResumePolicy>: ResumePolicy {
  public typealias Details = P.Details

  /// The inner resume policy being decorated.
  let inner: P

  /// The maximum number of total resume attempts allowed across the transfer.
  let maxTotalResumes: Int

  /// Creates a new `LimitedTotalResumes` decorator.
  ///
  /// Kept `internal` so callers construct decorated policies exclusively via the fluent
  /// ``ResumePolicy/withTotalResumeLimit(_:)`` method.
  ///
  /// - Parameters:
  ///   - inner: The underlying resume policy.
  ///   - maxTotalResumes: The maximum total resume count.
  ///     Clamped to be non-negative (`max(0, maxTotalResumes)`). Defaults to 10.
  init(_ inner: P, maxTotalResumes: Int = 10) {
    self.inner = inner
    self.maxTotalResumes = max(0, maxTotalResumes)
  }

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    switch inner.onError(state: state, error: error) {
    case .permanent(let e):
      return .permanent(e)
    case .exhausted(let e):
      return .exhausted(e)
    case .resume(let e):
      // `_ResumeLoop` increments `state.totalResumeCount` before consulting `onError`, so `>=`
      // halts once cumulative errors across the transfer reach `maxTotalResumes`.
      if state.totalResumeCount >= maxTotalResumes {
        return .exhausted(e)
      }
      return .resume(e)
    }
  }

  public func onProgress(state: inout ResumeState<Details>) {
    // Forward progress to inner policies (e.g., to reset consecutive error tracking) while
    // leaving `state.totalResumeCount` intact.
    inner.onProgress(state: &state)
  }

  public func remainingTime(state: ResumeState<Details>) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension LimitedTotalResumes: Equatable where P: Equatable {}

extension ResumePolicy {
  /// Decorates a ``ResumePolicy`` to limit total resume attempts.
  ///
  /// - Parameter maxTotalResumes: The maximum total resume count allowed.
  ///   Clamped to be non-negative (`max(0, maxTotalResumes)`). Defaults to 10.
  /// - Returns: A decorated resume policy.
  public func withTotalResumeLimit(_ maxTotalResumes: Int = 10) -> LimitedTotalResumes<Self> {
    LimitedTotalResumes(self, maxTotalResumes: maxTotalResumes)
  }
}
