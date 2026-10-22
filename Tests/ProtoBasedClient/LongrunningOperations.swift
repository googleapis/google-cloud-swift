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

  /// Starts a `createWorkflow` LRO and polls it to completion, retrying if the completed LRO
  /// operation payload itself reports a transient backend failure.
  ///
  /// While `testRetryOptions` (via `TestRetryPolicy`) automatically retries transient HTTP/RPC
  /// errors during the initial `createWorkflow` request and during `getOperation` polling calls,
  /// an LRO can also fail asynchronously on the backend after starting: `getOperation` returns
  /// HTTP 200 OK with `Operation(done: true, result: .error(status))` containing a transient code
  /// such as `INTERNAL` or `UNAVAILABLE`. Because the HTTP poll succeeded, the client's retry and
  /// polling error policies are not invoked, and `_PollableOperationImpl.wait()` throws the
  /// operation's `RequestError.service` directly. This helper catches such transient LRO errors
  /// and re-runs the operation.
  static private func createWorkflowWithRetry(
    client: WorkflowsClient,
    request: CreateWorkflowRequest,
    workflowName: String,
    logger: Logger,
    maxAttempts: Int = 3
  ) async throws -> Workflow {
    for attempt in 1...maxAttempts {
      do {
        return try await client.createWorkflowPollingUntilDone(
          request: request, options: testRetryOptions)
      } catch let error where error.isAlreadyExists {
        // If an earlier attempt succeeded on the backend before timing out or returning a
        // transient error, the retry with the same `workflowId` will receive `ALREADY_EXISTS`.
        // Fetch the existing workflow to continue the test.
        logger.info("createWorkflow() returned alreadyExists; fetching existing workflow")
        return try await client.getWorkflow(
          request: .init().with { $0.name = workflowName },
          options: testRetryOptions
        )
      } catch let error where error.isTransientTestError && attempt < maxAttempts {
        // The LRO completed with a transient error in `Operation.error` (or exhausted its per-call
        // retry budget on a transient error). Back off briefly and retry initiating the LRO.
        logger.info(
          "createWorkflow() LRO failed with transient error on attempt \(attempt): \(error); retrying"
        )
        try await Task.sleep(for: .seconds(attempt))
      }
    }
    preconditionFailure("maxAttempts must be greater than 0")
  }

  /// Starts a `deleteWorkflow` LRO and polls it to completion, retrying if the completed LRO
  /// operation payload reports a transient backend failure.
  static private func deleteWorkflowWithRetry(
    client: WorkflowsClient,
    workflowName: String,
    logger: Logger,
    maxAttempts: Int = 3
  ) async throws {
    for attempt in 1...maxAttempts {
      do {
        try await client.deleteWorkflowPollingUntilDone(
          request: .init().with { $0.name = workflowName },
          options: testRetryOptions
        )
        logger.info("deleteWorkflow() was successful")
        return
      } catch let error where error.isNotFound {
        // If an earlier attempt already deleted the workflow on the backend before failing or
        // timing out, a subsequent retry will return `NOT_FOUND`. Treat this as success.
        logger.info("deleteWorkflow() returned notFound (already deleted)")
        return
      } catch let error where error.isTransientTestError && attempt < maxAttempts {
        // The LRO completed with a transient error in `Operation.error` (or exhausted its per-call
        // retry budget on a transient error). Back off briefly and retry initiating the deletion.
        logger.info(
          "deleteWorkflow() LRO failed with transient error on attempt \(attempt): \(error); retrying"
        )
        try await Task.sleep(for: .seconds(attempt))
      }
    }
    preconditionFailure("maxAttempts must be greater than 0")
  }
}
