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

// snippet.show [START swift_enable_logging_full]
// snippet.imports [START swift_enable_logging_imports]
import Foundation
import GoogleCloudSecretManagerV1
import GoogleGax
import Logging
// snippet.end [END swift_enable_logging_imports]

// snippet.function [START swift_enable_logging_function]
func sample(projectId: String) async throws {
  // snippet.end [END swift_enable_logging_function]
  // snippet.logger [START swift_enable_logging_logger]
  var logger = Logger(label: "com.example.my-app")
  logger.logLevel = .debug
  // snippet.end [END swift_enable_logging_logger]
  // snippet.client [START swift_enable_logging_client]
  let client = try SecretManagerServiceClient(
    ClientOptions().with {
      $0.logger = logger
    })
  // snippet.end [END swift_enable_logging_client]
  // snippet.call [START swift_enable_logging_call]
  let secrets = client.listSecretsByItems(
    request: ListSecretsRequest().with { $0.parent = "projects/\(projectId)" })
  for try await item in secrets {
    print("  \(item)")
  }
  // snippet.end [END swift_enable_logging_call]
}
// snippet.hide [END swift_enable_logging_full]
@main struct SnippetRunner {
  static func main() async throws {
    try await sample(projectId: "[placeholder]")
  }
}
