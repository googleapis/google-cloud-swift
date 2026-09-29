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
import GoogleCloudAIPlatformV1
import Hummingbird
// snippet.end

// snippet.main [START swift_cloud_run_main]
@main
struct CloudRunGemini {
  static func main() async throws {
    // snippet.end [END swift_cloud_run_main]
    // snippet.config [START swift_cloud_run_config]
    let env = ProcessInfo.processInfo.environment
    guard let projectId = env["GOOGLE_CLOUD_PROJECT"], !projectId.isEmpty else {
      fatalError("GOOGLE_CLOUD_PROJECT environment variable is required")
    }
    let host = env["HOST"] ?? "0.0.0.0"
    let port = env["PORT"].flatMap(Int.init) ?? 8080
    // snippet.end [END swift_cloud_run_config]

    // snippet.client [START swift_cloud_run_client]
    let client = try PredictionServiceClient()
    let model = "projects/\(projectId)/locations/global/publishers/google/models/gemini-2.5-flash"
    // snippet.end [END swift_cloud_run_client]

    // snippet.router [START swift_cloud_run_router]
    let router = Router()
    router.get("/") { _, _ -> String in
      let request = GenerateContentRequest().with {
        $0.model = model
        $0.contents = [
          Content().with { content in
            content.role = "user"
            content.parts = [
              Part().with { part in
                part.data = .text(
                  "What's a good name for a flower shop that specializes in selling bouquets of dried flowers?"
                )
              }
            ]
          }
        ]
      }
      let response = try await client.generateContent(request: request)
      if case .text(let text) = response.candidates.first?.content?.parts.first?.data {
        return text
      }
      return "No response generated.\n"
    }
    // snippet.end [END swift_cloud_run_router]

    // snippet.run [START swift_cloud_run_run]
    let app = Application(
      router: router,
      configuration: .init(address: .hostname(host, port: port))
    )
    try await app.runService()
    // snippet.end [END swift_cloud_run_run]
  }
}
