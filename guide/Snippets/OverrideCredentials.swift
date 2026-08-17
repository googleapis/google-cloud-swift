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
import GoogleCloudAuth
import GoogleCloudGax
import GoogleCloudLanguageV2
// snippet.end

// snippet.function [START swift_override_credentials_function]
func sample(apiKey: String) async throws {
  // snippet.end [END swift_override_credentials_function]
  // snippet.client [START swift_override_credentials_client]
  let credentials = try Credentials(configuration: .apiKey(apiKey))
  let client = try LanguageServiceClient(
    ClientOptions().with { $0.credentials = credentials }
  )
  // snippet.end [END swift_override_credentials_client]
  // snippet.call [START swift_override_credentials_call]
  let document = Document().with {
    $0.type = .plainText
    $0.source = .content("Hello World!")
  }
  let response = try await client.analyzeSentiment(
    request: .init().with { $0.document = document })
  print("response=\(response)")
  // snippet.end [END swift_override_credentials_call]
}

// snippet.hide
@main struct SnippetRunner {
  static func main() async throws {
    try await sample(apiKey: "[placeholder]")
  }
}
