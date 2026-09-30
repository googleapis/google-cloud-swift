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

// snippet.show [START swift_update_resource_field]
// snippet.imports
import Foundation
import GoogleCloudSecretManagerV1
// snippet.end

// snippet.function [START swift_update_resource_function]
func sample(projectId: String, secretId: String) async throws {
  // snippet.end [END swift_update_resource_function]
  // snippet.create [START swift_update_resource_create]
  let client = try SecretManagerServiceClient()

  let secret = try await client.createSecret(
    parent: "projects/\(projectId)",
    secretId: secretId,
    secret: Secret().with {
      $0.replication = Replication().with { replication in
        replication.replication = .automatic(Replication.Automatic())
      }
    }
  )
  print("CREATE = \(secret)")
  // snippet.end [END swift_update_resource_create]

  // snippet.update [START swift_update_resource_update]
  var labels = secret.labels
  labels["updated"] = "your-label"
  var annotations = secret.annotations
  annotations["updated"] = "your-annotations"

  let updatedSecret = Secret().with {
    $0.name = secret.name
    $0.etag = secret.etag
    $0.labels = labels
    $0.annotations = annotations
  }
  // snippet.end [END swift_update_resource_update]

  // snippet.update_mask [START swift_update_resource_set_update_mask]
  let update = try await client.updateSecret(
    secret: updatedSecret,
    updateMask: ["annotations", "labels"]
  )
  print("UPDATE = \(update)")
  // snippet.end [END swift_update_resource_set_update_mask]
}
// snippet.hide [END swift_update_resource_field]

@main struct SnippetRunner {
  static func main() async throws {
    try await sample(projectId: "[placeholder]", secretId: "your-secret")
  }
}
