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

/// A retry policy decorator that limits the total time in the retry loop.
///
/// If the time elapsed in the retry loop, including any backoff, is larger than the prescribed
/// duration then the policy returns ``RetryResult/exhausted(_:)``. Otherwise, the policy returns
/// the result from the inner policy.
///
/// The `remainingTime()` method returns the remaining time. This is always zero after the
/// policy's deadline is reached.
final public class LimitedElapsedTime<P: Sendable>: Sendable {
  let inner: P
  let maximumDuration: Duration

  public init(inner: P, maximumDuration: Duration) {
    self.inner = inner
    self.maximumDuration = maximumDuration
  }
}
