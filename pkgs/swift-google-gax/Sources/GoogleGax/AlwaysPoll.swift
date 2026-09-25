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

/// A polling policy that continues polling on all errors.
///
/// Use ``unbounded()`` decorated with ``PollingErrorPolicy/withTimeLimit(_:)``
/// and/or ``PollingErrorPolicy/withAttemptLimit(_:)`` to configure bounds.
///
/// The policy continues on all errors. This may be useful in tests, or to just poll for a fixed
/// number of attempts or fixed amount of time.
public struct AlwaysPoll: PollingErrorPolicy, Sendable, Equatable {
  public init() {}

  /// Creates an unconstrained polling error policy that continues polling on all errors indefinitely.
  ///
  /// Decorate this policy with ``PollingErrorPolicy/withTimeLimit(_:)`` and/or
  /// ``PollingErrorPolicy/withAttemptLimit(_:)`` to bound the polling loop:
  /// ```swift
  /// let policy = AlwaysPoll.unbounded()
  ///   .withTimeLimit(.seconds(10 * 60))
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators,
  ///   this policy continues polling on errors indefinitely.
  public static func unbounded() -> AlwaysPoll {
    AlwaysPoll()
  }

  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    .retry(error)
  }
}
