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
import GoogleCloudGax
import GoogleCloudWorkflowsV1
// snippet.end

// snippet.function [START swift_long_running_operations_function]
func sample(projectId: String, location: String, workflowId: String) async throws {
  // snippet.end [END swift_long_running_operations_function]
  // snippet.client [START swift_long_running_operations_client]
  let client = try WorkflowsClient()
  // snippet.end [END swift_long_running_operations_client]
  // snippet.call [START swift_long_running_operations_call]
  let workflow = Workflow().with {
    $0.description = "A sample workflow"
    $0.sourceCode = .sourceContents(
      """
      main:
        steps:
          - returnStep:
              return "Hello World!"
      """
    )
  }
  let operation = try await client.createWorkflow(
    parent: "projects/\(projectId)/locations/\(location)",
    workflow: workflow,
    workflowId: workflowId
  )
  // snippet.end [END swift_long_running_operations_call]
  // snippet.wait [START swift_long_running_operations_wait]
  let response = try await operation.wait()
  print("Workflow created: \(response.name)")
  // snippet.end [END swift_long_running_operations_wait]
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
