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

struct StructuredLog: Codable, Sendable {
  let severity: String
  let labels: [String: String]
  let message: String
}

private let logEncoder: JSONEncoder = {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return encoder
}()

func reportRetryPolicyError(
  _ error: RequestError,
  method: String,
  state: RetryState,
  result: RetryResult,
  task: String = "worker"
) {
  let elapsed = ContinuousClock.now - state.start
  let verdict: String
  switch result {
  case .exhausted: verdict = "exhausted"
  case .permanent: verdict = "permanent"
  case .retry: verdict = "retry"
  }
  let log = StructuredLog(
    severity: "error",
    labels: [
      "application": "storage-w1r3",
      "policyType": "retry",
      "verdict": verdict,
      "idempotent": "\(state.idempotent)",
      "elapsed": "\(elapsed)",
      "attemptCount": "\(state.attemptCount)",
      "method": method,
      "task": task,
    ],
    message: "\(error)"
  )
  if let data = try? logEncoder.encode(log),
    let jsonString = String(data: data, encoding: .utf8)
  {
    FileHandle.standardError.write(Data((jsonString + "\n").utf8))
  }
}

func reportResumePolicyError<Details>(
  _ error: RequestError,
  operation: String,
  state: ResumeState<Details>,
  result: ResumeResult,
  task: String = "worker"
) {
  let elapsed = ContinuousClock.now - state.start
  let verdict: String
  switch result {
  case .exhausted: verdict = "exhausted"
  case .permanent: verdict = "permanent"
  case .resume: verdict = "resume"
  }
  let log = StructuredLog(
    severity: "error",
    labels: [
      "application": "storage-w1r3",
      "policyType": "resume",
      "verdict": verdict,
      "idempotent": "\(state.idempotent)",
      "elapsed": "\(elapsed)",
      "attemptCount": "\(state.totalResumeCount)",
      "consecutiveErrorCount": "\(state.consecutiveErrorCount)",
      "operation": operation,
      "task": task,
    ],
    message: "\(error)"
  )
  if let data = try? logEncoder.encode(log),
    let jsonString = String(data: data, encoding: .utf8)
  {
    FileHandle.standardError.write(Data((jsonString + "\n").utf8))
  }
}
