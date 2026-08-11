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

/// Implements a linear backoff policy with constant delay.
///
/// This class conforms to the ``BackoffPolicy`` protocol. It implements a simple linear backoff
/// algorithm, where the delay between retry attempts remains constant.
public final class LinearBackoffPolicy: BackoffPolicy, Sendable {
  public let delay: Duration

  /// Create a new linear backoff policy with the specified constant delay.
  public init(delay: Duration = .seconds(5)) {
    self.delay = delay
  }

  public func backoffDelayFor(_ state: RetryState) -> Duration {
    return self.delay
  }
}
