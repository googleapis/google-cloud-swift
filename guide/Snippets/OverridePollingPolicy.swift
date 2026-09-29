// snippet.hide
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

// snippet.show
// snippet.imports
import Foundation
import GoogleGax
import GoogleCloudWorkflowsV1
// snippet.end

// snippet.function [START swift_override_polling_policy_function]
func sample(projectId: String, location: String, workflowId: String) async throws {
  // snippet.end [END swift_override_polling_policy_function]
  // snippet.client [START swift_override_polling_policy_client]
  let client = try WorkflowsClient(
    ClientOptions().with {
      $0.pollingErrorPolicy = BasePollingErrorPolicy.unbounded()
        .withTimeLimit(.seconds(5 * 60))
        .withAttemptLimit(20)
    })
  // snippet.end [END swift_override_polling_policy_client]
  // snippet.backoff [START swift_override_polling_policy_backoff]
  let fasterClient = try WorkflowsClient(
    ClientOptions().with {
      $0.pollingErrorPolicy = BasePollingErrorPolicy.unbounded()
        .withTimeLimit(.seconds(5 * 60))
        .withAttemptLimit(20)
      $0.pollingBackoffPolicy = ExponentialBackoff(
        clamping: ExponentialBackoffConfig().with {
          $0.initialDelay = .milliseconds(500)
          $0.maximumDelay = .seconds(10)
          $0.scaling = 1.5
        })
    })
  try await fasterClient.deleteWorkflowPollingUntilDone(
    name: "projects/\(projectId)/locations/\(location)/workflows/\(workflowId)"
  )
  // snippet.end [END swift_override_polling_policy_backoff]
  // snippet.request [START swift_override_polling_policy_request]
  let options = RequestOptions().with {
    $0.pollingErrorPolicy = BasePollingErrorPolicy.unbounded().withTimeLimit(.seconds(60))
    $0.pollingBackoffPolicy = ExponentialBackoff(
      clamping: ExponentialBackoffConfig().with {
        $0.initialDelay = .milliseconds(250)
        $0.maximumDelay = .seconds(5)
      })
  }
  try await client.deleteWorkflowPollingUntilDone(
    request: DeleteWorkflowRequest().with {
      $0.name = "projects/\(projectId)/locations/\(location)/workflows/\(workflowId)"
    },
    options: options)
  // snippet.end [END swift_override_polling_policy_request]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await sample(
      projectId: "[placeholder]",
      location: "us-central1",
      workflowId: "my-workflow"
    )
  }
}
