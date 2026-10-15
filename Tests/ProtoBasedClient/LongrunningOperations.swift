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
import GoogleGax
import GoogleCloudTestHelpers
import GoogleWKT
import GoogleCloudWorkflowsV1
import Logging
import Testing

/// Run tests for LROs.
public enum LongrunningOperations {
  static public func run(_ logger: Logger) async throws {
    let project = try projectId()
    let location = locationId()
    let runner = try testServiceAccount()

    try await createAndDeleteWorkflow(
      projectId: project, location: location, runner: runner, logger: logger)
  }

  static private func createAndDeleteWorkflow(
    projectId: String, location: String, runner: String, logger: Logger
  )
    async throws
  {
    let client = try WorkflowsClient(testClientOptions)
    let workflowId =
      "test_wf_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_").prefix(20))"
    let parent = "projects/\(projectId)/locations/\(location)"
    let workflowName = "\(parent)/workflows/\(workflowId)"

    logger.info("Testing createWorkflow()")
    let create = CreateWorkflowRequest().with {
      $0.parent = parent
      $0.workflowId = workflowId
      $0.workflow = Workflow().with { workflow in
        workflow.description = "Test workflow created by integration test"
        workflow.labels = ["integration-test": "true"]
        workflow.serviceAccount = runner
        workflow.sourceCode = .sourceContents(
          """
          - init:
              assign:
                - message: "Hello World"
          - finish:
              return: ${message}
          """
        )
      }
    }

    logger.info("create = \(create)")

    let workflow = try await createWorkflowWithRetry(
      client: client, request: create, workflowName: workflowName, logger: logger)
    logger.info("createWorkflow() was successful")
    #expect(workflow.name == workflowName)

    logger.info("\nTesting deleteWorkflow() for \(workflow.name)")
    try await deleteWorkflowWithRetry(
      client: client, workflowName: workflow.name, logger: logger)
  }

  static private func createWorkflowWithRetry(
    client: WorkflowsClient,
    request: CreateWorkflowRequest,
    workflowName: String,
    logger: Logger,
    maxAttempts: Int = 3
  ) async throws -> Workflow {
    var lastError: (any Error)?
    for attempt in 1...maxAttempts {
      do {
        return try await client.createWorkflowPollingUntilDone(
          request: request, options: testRetryOptions)
      } catch let error where error.isAlreadyExists {
        // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
        logger.info("createWorkflow() returned alreadyExists; fetching existing workflow")
        return try await client.getWorkflow(
          request: .init().with { $0.name = workflowName },
          options: testRetryOptions
        )
      } catch let error where error.isTransientTestError && attempt < maxAttempts {
        // An LRO may complete with a transient error in `Operation.error` (where the HTTP poll
        // itself returned 200 OK). Retry the LRO after a short delay.
        lastError = error
        logger.info(
          "createWorkflow() LRO failed with transient error on attempt \(attempt): \(error); retrying"
        )
        try await Task.sleep(for: .seconds(attempt))
      }
    }
    throw lastError!
  }

  static private func deleteWorkflowWithRetry(
    client: WorkflowsClient,
    workflowName: String,
    logger: Logger,
    maxAttempts: Int = 3
  ) async throws {
    var lastError: (any Error)?
    for attempt in 1...maxAttempts {
      do {
        try await client.deleteWorkflowPollingUntilDone(
          request: .init().with { $0.name = workflowName },
          options: testRetryOptions
        )
        logger.info("deleteWorkflow() was successful")
        return
      } catch let error where error.isNotFound {
        // This error is acceptable because we retry a non-idempotent operation, the alternative is flakes in our CI.
        logger.info("deleteWorkflow() returned notFound (already deleted)")
        return
      } catch let error where error.isTransientTestError && attempt < maxAttempts {
        lastError = error
        logger.info(
          "deleteWorkflow() LRO failed with transient error on attempt \(attempt): \(error); retrying"
        )
        try await Task.sleep(for: .seconds(attempt))
      }
    }
    throw lastError!
  }
}
