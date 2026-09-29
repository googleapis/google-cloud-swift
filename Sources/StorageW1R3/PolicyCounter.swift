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

/// A thread-safe atomic counter for tracking policy consultations across concurrent tasks.
public final class PolicyCounter: Sendable {
  private let count: Atomic<UInt64>

  public init(initialValue: UInt64 = 0) {
    self.count = Atomic(initialValue)
  }

  /// Increments the counter by 1.
  public func increment() {
    count.add(1, ordering: .relaxed)
  }

  /// The current value of the counter.
  public var value: UInt64 {
    count.load(ordering: .relaxed)
  }
}

/// Global counters tracking retry and resume policy consultations across the benchmark.
public enum GlobalCounters {
  public static let retryPolicy = PolicyCounter()
  public static let resumePolicy = PolicyCounter()
}
