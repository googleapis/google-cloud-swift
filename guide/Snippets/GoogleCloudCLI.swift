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
import GoogleCloudSecretManagerV1
// snippet.end

// snippet.main
@main
struct GoogleCloudCLI {
  static func main() async throws {
    // snippet.end
    // snippet.args
    let args = CommandLine.arguments.dropFirst()
    guard let projectId = args.first else {
      print("Usage: GoogleCloudCLI <projectId>")
      exit(1)
    }
    // snippet.end
    // snippet.client
    let client = try SecretManagerServiceClient()
    // snippet.end
    // snippet.list
    let secrets = try client.listSecrets(
      byItem: ListSecretsRequest().with { $0.parent = "projects/\(projectId)" })
    for try await item in secrets {
      print("  \(item)")
    }
    // snippet.end
  }
}
