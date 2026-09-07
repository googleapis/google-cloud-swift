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
import Synchronization

/// A thread-safe counter for tracking retry attempts across workers and retry policies.
public final class RetryAttemptCounter: Sendable {
  private let count: Atomic<UInt64>

  public init(initialValue: UInt64 = 0) {
    self.count = Atomic(initialValue)
  }

  /// Increments the retry attempt counter by 1.
  public func recordRetryAttempt() {
    count.add(1, ordering: .relaxed)
  }

  /// Increments the retry attempt counter by 1.
  public func increment() {
    count.add(1, ordering: .relaxed)
  }

  /// The current number of retry attempts recorded.
  public var value: UInt64 {
    count.load(ordering: .relaxed)
  }

  /// The current number of retry attempts recorded.
  public var countValue: UInt64 {
    value
  }
}

public typealias RetryCounter = RetryAttemptCounter

/// A thread-safe metrics tracker for aggregating request counts across concurrent workers.
actor MetricsTracker {
  private var totalSuccessCount: UInt64 = 0
  private var totalErrorCount: UInt64 = 0
  private var totalUpdateCount: UInt64 = 0
  let retryAttempts: RetryAttemptCounter

  init(retryAttempts: RetryAttemptCounter = RetryAttemptCounter()) {
    self.retryAttempts = retryAttempts
  }

  func record(
    successes: UInt64,
    errors: UInt64,
    updates: UInt64
  ) -> (totalSuccess: UInt64, totalError: UInt64, totalUpdate: UInt64, totalRetry: UInt64) {
    totalSuccessCount += successes
    totalErrorCount += errors
    totalUpdateCount += updates
    return (totalSuccessCount, totalErrorCount, totalUpdateCount, retryAttempts.value)
  }

  func recordRetryAttempt() {
    retryAttempts.recordRetryAttempt()
  }
}
