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
import GoogleCloudGax
import GoogleRpc

/// A base retry policy for Google Cloud Storage that retries transient errors on idempotent requests.
///
/// This policy retries idempotent operations that fail with I/O errors, transient HTTP status codes
/// (408, 429, and 5xx), or transient gRPC status codes (`unavailable`, `resourceExhausted`,
/// `deadlineExceeded`, and `internal`).
///
/// This policy must be decorated to limit the number of retry attempts or the duration of the
/// retry loop.
public final class StorageBaseRetryPolicy: Sendable {
  let inner: StrictIdempotency<ContinueOnIO<StorageRetryErrors>>

  public init() {
    self.inner = StorageRetryErrors().retryOnIO().strictIdempotency()
  }

  /// The default retry policy for Google Cloud Storage, with a 60-second time limit and 10-attempt limit.
  package static var defaultPolicy: any RetryPolicy {
    StorageBaseRetryPolicy().withTimeLimit(.seconds(60)).withAttemptLimit(10)
  }
}

extension StorageBaseRetryPolicy: RetryPolicy {
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
