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
import GoogleCloudSecretManagerV1
// snippet.end

// snippet.function [START swift_override_endpoint_function]
func sample(projectId: String, region: String) async throws {
// snippet.end [END swift_override_endpoint_function]
  // snippet.client [START swift_override_endpoint_client]
  let client = try SecretManagerServiceClient(ClientOptions().with {
    $0.endpoint = "https://secretmanager.\(region).rep.googleapis.com"
  })
  // snippet.end [END swift_override_endpoint_client]
  // snippet.list [START swift_override_endpoint_list]
  let secrets = try client.listSecrets(
    byItem: ListSecretsRequest().with { $0.parent = "projects/\(projectId)/locations/\(region)" })
  for try await item in secrets {
    print("  \(item)")
  }
  // snippet.end [END swift_override_endpoint_list]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await sample(projectId: "[placeholder]", region: "us-central1")
  }
}
