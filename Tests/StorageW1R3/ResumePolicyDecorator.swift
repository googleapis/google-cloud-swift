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
import GoogleCloudStorage

/// A resume policy decorator that counts each policy consultation and logs details
/// when the policy returns "exhausted" or "permanent".
public struct ResumePolicyDecorator<P: ResumePolicy>: ResumePolicy {
  public typealias Details = P.Details

  public let inner: P
  public let counter: PolicyCounter
  public let operationName: String
  public let task: String

  public init(
    inner: P,
    counter: PolicyCounter = GlobalCounters.resumePolicy,
    operationName: String,
    task: String = "worker"
  ) {
    self.inner = inner
    self.counter = counter
    self.operationName = operationName
    self.task = task
  }

  public func onError(state: ResumeState<Details>, error: RequestError) -> ResumeResult {
    let result = inner.onError(state: state, error: error)
    counter.increment()
    switch result {
    case .resume:
      break
    case .permanent, .exhausted:
      reportResumePolicyError(
        error, operation: operationName, state: state, result: result, task: task)
    }
    return result
  }

  public func onProgress(state: inout ResumeState<Details>) {
    inner.onProgress(state: &state)
  }

  public func remainingTime(state: ResumeState<Details>) -> Duration? {
    inner.remainingTime(state: state)
  }
}

extension ResumePolicy {
  /// Decorates this resume policy to count consultations and log exhausted or permanent errors.
  public func countedAndLogged(
    counter: PolicyCounter = GlobalCounters.resumePolicy,
    operationName: String,
    task: String = "worker"
  ) -> ResumePolicyDecorator<Self> {
    ResumePolicyDecorator(inner: self, counter: counter, operationName: operationName, task: task)
  }
}
