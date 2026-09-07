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

/// A retry policy decorator that counts each retry attempt and logs errors with the retry attempt
/// and the name of the method that failed.
public struct RetryPolicyDecorator<P: RetryPolicy>: RetryPolicy {
  public let inner: P
  public let counter: RetryAttemptCounter
  public let methodName: String
  public let task: String

  public init(
    inner: P,
    counter: RetryAttemptCounter,
    methodName: String,
    task: String = "worker"
  ) {
    self.inner = inner
    self.counter = counter
    self.methodName = methodName
    self.task = task
  }

  public func onError(state: RetryState, error: RequestError) -> RetryResult {
    let result = inner.onError(state: state, error: error)
    counter.recordRetryAttempt()
    switch result {
    case .retry:
      break
    case .permanent, .exhausted:
      reportRetryError(error, method: methodName, state: state, task: task)
      break
    }
    return result
  }

  public func onThrottle(state: RetryState, error: RequestError) -> ThrottleResult {
    inner.onThrottle(state: state, error: error)
  }

  public func remainingTime(state: RetryState) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension RetryPolicy {
  /// Decorates this retry policy to count retry attempts and log errors with method name and attempt count.
  public func countedAndLogged(
    counter: RetryAttemptCounter,
    methodName: String,
    task: String = "worker"
  ) -> RetryPolicyDecorator<Self> {
    RetryPolicyDecorator(inner: self, counter: counter, methodName: methodName, task: task)
  }
}
