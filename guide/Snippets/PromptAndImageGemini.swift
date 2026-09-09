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
// snippet.end

// snippet.function [START swift_prompt_and_image]
func sample(projectId: String) async throws {
  // snippet.end [END swift_prompt_and_image]
  // snippet.client [START swift_prompt_and_image_client]
  let client = try PredictionServiceClient()
  // snippet.end [END swift_prompt_and_image_client]

  // snippet.model [START swift_prompt_and_image_model]
  let model = "projects/\(projectId)/locations/global/publishers/google/models/gemini-3.8-flash"
  // snippet.end [END swift_prompt_and_image_model]

  // snippet.image_part [START swift_prompt_and_image_image_part]
  let imagePart = Part().with {
    $0.data = .fileData(
      FileData().with { fileData in
        fileData.mimeType = "image/jpeg"
        fileData.fileUri = "gs://generativeai-downloads/images/scones.jpg"
      }
    )
  }
  // snippet.end [END swift_prompt_and_image_image_part]

  // snippet.prompt_part [START swift_prompt_and_image_prompt_part]
  let textPart = Part().with {
    $0.data = .text("Describe this picture.")
  }
  // snippet.end [END swift_prompt_and_image_prompt_part]

  // snippet.request [START swift_prompt_and_image_request]
  let request = GenerateContentRequest().with {
    $0.model = model
    $0.contents = [
      Content().with { content in
        content.role = "user"
        content.parts = [imagePart, textPart]
      }
    ]
  }
  let response = try await client.generateContent(request: request)
  // snippet.end [END swift_prompt_and_image_request]
  // snippet.response [START swift_prompt_and_image_response]
  print("RESPONSE = \(response)")
  // snippet.end [END swift_prompt_and_image_response]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    let projectId = CommandLine.arguments.dropFirst().first ?? "[placeholder]"
    try await sample(projectId: projectId)
  }
}
