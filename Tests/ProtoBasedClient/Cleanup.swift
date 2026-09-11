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
import GoogleCloudSecretManagerV1
import GoogleCloudTestHelpers
import GoogleCloudWorkflowsV1

func cleanupStaleSecrets() async {
  do {
    try await cleanupStaleSecretsImpl()
  } catch {
    print("Error cleaning up stale secrets: \(error)")
  }
}

func cleanupStaleSecretsImpl() async throws {
  let projectId = try projectId()
  let client = try SecretManagerServiceClient()
  let secrets = try client.listSecrets(
    byItem: .init().with { $0.parent = "projects/\(projectId)" },
    options: testRetryOptions
  )

  // Wait at least 48 hours before deleting the resources.
  let slack = UInt64(48 * 3600)
  let deadline = UInt64(Date().timeIntervalSince1970) - slack
  for try await secret in secrets {
    guard let v = secret.labels["integration-test"], v == "true" else {
      continue
    }
    guard let t = secret.createTime, t.seconds < deadline else {
      continue
    }
    do {
      try await client.deleteSecret(
        request: .init().with {
          $0.name = secret.name
          $0.etag = secret.etag
        },
        options: testRetryOptions
      )
    } catch let error where error.isNotFound || error.isFailedPreconditionOrAborted {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      continue
    }
  }
}

func cleanUpStaleWorkflows() async {
  do {
    try await cleanUpStaleWorkflowsImpl()
  } catch {
    print("Error cleaning up stale workflows: \(error)")
  }
}

func cleanUpStaleWorkflowsImpl() async throws {
  let projectId = try projectId()
  let location = locationId()
  let client = try WorkflowsClient()
  let workflows = try client.listWorkflows(
    byItem: .init().with {
      $0.parent = "projects/\(projectId)/locations/\(location)"
    },
    options: testRetryOptions
  )

  // Wait at least 48 hours before deleting the resources.
  let slack = UInt64(48 * 3600)
  let deadline = UInt64(Date().timeIntervalSince1970) - slack
  for try await workflow in workflows {
    guard let v = workflow.labels["integration-test"], v == "true" else {
      continue
    }
    guard let t = workflow.createTime, t.seconds < deadline else {
      continue
    }
    do {
      // Start deletion and don't wait for it to complete.
      _ = try await client.deleteWorkflow(
        request: .init().with { $0.name = workflow.name },
        options: testRetryOptions
      )
    } catch let error where error.isNotFound {
      // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
      continue
    }
  }
}
