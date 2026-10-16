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

// snippet.show [START swift_occ_iam_full]
// snippet.imports [START swift_occ_iam_imports]
import Foundation
import GoogleCloudSecretManagerV1
import GoogleGax
import GoogleIAMV1
// snippet.end [END swift_occ_iam_imports]

// snippet.function [START swift_occ_iam_function]
func addIamMember(
  projectId: String,
  secretId: String,
  role: String,
  member: String
) async throws -> Policy {
  // snippet.end [END swift_occ_iam_function]
  // snippet.client [START swift_occ_iam_client]
  let client = try SecretManagerServiceClient()
  let backoff = ExponentialBackoff(
    clamping: ExponentialBackoffConfig().with {
      $0.initialDelay = .milliseconds(250)
      $0.maximumDelay = .seconds(5)
      $0.scaling = 2.0
    })
  let maxAttempts = 5
  let resource = "projects/\(projectId)/secrets/\(secretId)"
  // snippet.end [END swift_occ_iam_client]

  // snippet.loop [START swift_occ_iam_loop]
  var attempt = 0
  while true {
    attempt += 1
    var policy = try await client.getIamPolicy(
      request: GetIamPolicyRequest().with {
        $0.resource = resource
        $0.options = GetPolicyOptions().with { options in
          options.requestedPolicyVersion = 3
        }
      })

    if let index = policy.bindings.firstIndex(where: { $0.role == role && $0.condition == nil }) {
      if policy.bindings[index].members.contains(member) {
        return policy
      }
      policy.bindings[index].members.append(member)
    } else {
      policy.bindings.append(
        Binding().with {
          $0.role = role
          $0.members = [member]
        })
    }

    do {
      return try await client.setIamPolicy(
        request: SetIamPolicyRequest().with {
          $0.resource = resource
          $0.policy = policy
        })
    } catch RequestError.service(let serviceError) where serviceError.code == .aborted {
      guard attempt < maxAttempts else {
        throw RequestError.service(serviceError)
      }
      let delay = backoff.backoffDelay(
        for: RetryState().with {
          $0.attemptCount = attempt
        })
      try await Task.sleep(for: delay)
    }
  }
  // snippet.end [END swift_occ_iam_loop]
}
// snippet.hide [END swift_occ_iam_full]

@main struct SnippetRunner {
  static func main() async throws {
    let updated = try await addIamMember(
      projectId: "[placeholder]",
      secretId: "my-secret",
      role: "roles/secretmanager.secretAccessor",
      member: "user:alice@example.com"
    )
    print("Updated IAM policy: \(updated)")
  }
}
