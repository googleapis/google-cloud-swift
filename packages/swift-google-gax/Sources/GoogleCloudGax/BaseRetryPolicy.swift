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

/// A combination of retry policies that works for most services.
///
/// This policy must be decorated to limit the number of retry attempts or the duration of the
/// retry loop.
///
/// This policy only retries [idempotent] operations, and then only if the error is an I/O error, or a safe error code.
///
/// [AIP-194]: https://google.aip.dev/194
final public class BaseRetryPolicy: RetryPolicy {
  let inner: StrictIdempotency<ContinueOnIO<Aip194>>

  public init() {
    self.inner = Aip194().retryOnIO().strictIdempotency()
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    self.inner.onError(state: state, error: error)
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    self.inner.onThrottle(state: state, error: error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    self.inner.remainingTime(state: state)
  }
}
