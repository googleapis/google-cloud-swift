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
import GoogleRpc

/// A combination of polling error policies that works for most services.
///
/// Use ``defaultPolicy`` for the standard bounded configuration (30-minute time limit), or
/// ``unbounded()`` decorated with ``PollingErrorPolicy/withTimeLimit(_:)`` and/or
/// ``PollingErrorPolicy/withAttemptLimit(_:)`` to configure custom limits.
///
/// This policy only continues if the error is an I/O error, or a safe error code.
///
/// [AIP-194]: https://google.aip.dev/194
public struct BasePollingErrorPolicy: PollingErrorPolicy, Sendable, Equatable {
  let inner: TooManyRequests<ContinueOnIO<Aip194>>

  public init() {
    self.inner = Aip194().continueOnIoErrors().continueOnTooManyRequests()
  }

  /// Creates an unconstrained base polling error policy without attempt or time limits.
  ///
  /// Decorate this policy with ``PollingErrorPolicy/withTimeLimit(_:)`` and/or
  /// ``PollingErrorPolicy/withAttemptLimit(_:)`` to bound the polling loop:
  /// ```swift
  /// let policy = BasePollingErrorPolicy.unbounded()
  ///   .withTimeLimit(.seconds(10 * 60))
  /// ```
  ///
  /// - Warning: Without `.withAttemptLimit(_:)` or `.withTimeLimit(_:)` decorators,
  ///   this policy continues polling on transient errors indefinitely.
  public static func unbounded() -> BasePollingErrorPolicy {
    BasePollingErrorPolicy()
  }

  /// The default polling error policy, with a 30-minute time limit.
  public static var defaultPolicy: some PollingErrorPolicy {
    BasePollingErrorPolicy.unbounded().withTimeLimit(.seconds(30 * 60))
  }

  public func onError(state: PollingState, error: RequestError) -> PollingResult {
    self.inner.onError(state: state, error: error)
  }

  public func onInProgress(state: PollingState) throws {
    try self.inner.onInProgress(state: state)
  }
}
