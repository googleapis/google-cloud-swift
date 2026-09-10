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

/// The input into a polling policy query.
///
/// On an error, the client library queries the polling policy as to whether it
/// should make a new attempt. The client library provides an instance of this
/// type to this policy.
///
/// This struct may gain new fields in future versions of the client libraries.
public struct PollingState: Sendable {
  /// The start time for this retry loop.
  public var start: ContinuousClock.Instant

  /// The number of times the request has been attempted.
  public var attemptCount: UInt32

  /// Create a new instance.
  public init() {
    self.start = ContinuousClock.now
    self.attemptCount = 0
  }

  /// Override specific values using the `Then` idiom.
  ///
  /// ## Example
  /// ```
  /// let state = PollingState().with { $0.attemptCount = 1 }
  /// ```
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}
