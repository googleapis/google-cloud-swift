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
import Testing
import Logging
import GoogleCloudTestHelpers
import GoogleCloudWkt
import GoogleCloudWorkflowsV1

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
    let client = try WorkflowsClient()
    let workflowId =
      "test_wf_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_").prefix(20))"
    let parent = "projects/\(projectId)/locations/\(location)"

    logger.info("Testing createWorkflow()")
    let create = CreateWorkflowRequest().with {
      $0.parent = parent
      $0.workflowId = workflowId
      $0.workflow = Workflow().with {
        $0.description = "Test workflow created by integration test"
        $0.labels = ["integration-test": "true"]
        $0.serviceAccount = runner
        $0.sourceCode = .sourceContents(
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

    let createLro = try await client.createWorkflow(withPolling: create)
    let workflow = try await createLro.wait()
    logger.info("createWorkflow() was successful")
    #expect(workflow.name == "\(parent)/workflows/\(workflowId)")

    logger.info("\nTesting deleteWorkflow() for \(workflow.name)")
    let deleteLro = try await client.deleteWorkflow(
      withPolling: .init().with { $0.name = workflow.name })
    _ = try await deleteLro.wait()
    logger.info("deleteWorkflow() was successful")
  }
}
