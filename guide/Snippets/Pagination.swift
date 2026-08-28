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

// snippet.function [START swift_pagination_auto_function]
func iterateItems(projectId: String) async throws {
  // snippet.end [END swift_pagination_auto_function]
  // snippet.client [START swift_pagination_client]
  let client = try SecretManagerServiceClient()
  // snippet.end [END swift_pagination_client]
  // snippet.auto [START swift_pagination_auto]
  let request = ListSecretsRequest().with {
    $0.parent = "projects/\(projectId)"
    $0.pageSize = 25
  }
  let secrets = try client.listSecrets(byItem: request)
  for try await secret in secrets {
    print("Secret name: \(secret.name)")
  }
  // snippet.end [END swift_pagination_auto]
}

// snippet.manual_function [START swift_pagination_manual_function]
func iteratePages(projectId: String) async throws {
  let client = try SecretManagerServiceClient()
  // snippet.end [END swift_pagination_manual_function]
  // snippet.manual [START swift_pagination_manual]
  var request = ListSecretsRequest().with {
    $0.parent = "projects/\(projectId)"
    $0.pageSize = 25
  }
  while true {
    let response = try await client.listSecrets(request: request)
    for secret in response.secrets {
      print("Secret name: \(secret.name)")
    }
    if response.nextPageToken.isEmpty {
      break
    }
    request.pageToken = response.nextPageToken
  }
  // snippet.end [END swift_pagination_manual]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await iterateItems(projectId: "[placeholder]")
    try await iteratePages(projectId: "[placeholder]")
  }
}
