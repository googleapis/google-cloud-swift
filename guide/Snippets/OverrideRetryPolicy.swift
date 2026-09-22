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
import GoogleCloudSecretManagerV1
// snippet.end

// snippet.function [START swift_override_retry_policy_function]
func sample(projectId: String) async throws {
  // snippet.end [END swift_override_retry_policy_function]
  // snippet.client [START swift_override_retry_policy_client]
  let client = try SecretManagerServiceClient(
    ClientOptions().with {
      $0.retryPolicy = BaseRetryPolicy.unbounded().withTimeLimit(.seconds(10)).withAttemptLimit(3)
    })
  // snippet.end [END swift_override_retry_policy_client]
  // snippet.backoff [START swift_override_retry_policy_backoff]
  let slowerClient = try SecretManagerServiceClient(
    ClientOptions().with {
      $0.retryPolicy = BaseRetryPolicy.unbounded().withTimeLimit(.seconds(10)).withAttemptLimit(3)
      $0.backoffPolicy = ExponentialBackoff(
        clamping: ExponentialBackoffConfig().with {
          $0.initialDelay = .milliseconds(250)
          $0.maximumDelay = .seconds(5)
          $0.scaling = 1.5
        })
    })
  // snippet.end [END swift_override_retry_policy_backoff]
  // snippet.request [START swift_override_retry_policy_request]
  let options = RequestOptions().with {
    $0.retryPolicy = NeverRetry()
  }
  let secret = try await client.getSecret(
    request: GetSecretRequest().with { $0.name = "projects/\(projectId)/secrets/my-secret" },
    options: options)
  print("secret: \(secret)")
  // snippet.end [END swift_override_retry_policy_request]
  // snippet.idempotency [START swift_override_retry_policy_idempotency]
  let retried = RequestOptions().with {
    $0.retryPolicy = BaseRetryPolicy.unbounded().withTimeLimit(.seconds(30))
    $0.idempotency = true
  }
  try await slowerClient.deleteSecret(
    request: DeleteSecretRequest().with {
      $0.name = "projects/\(projectId)/secrets/my-secret"
      $0.etag = "\"an-etag-from-a-previous-read\""
    },
    options: retried)
  // snippet.end [END swift_override_retry_policy_idempotency]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await sample(projectId: "[placeholder]")
  }
}
