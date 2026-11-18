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
import Foundation
import GoogleAuth

struct CustomOIDCSubjectTokenProvider: SubjectTokenProvider {
  let idToken: String

  func subjectToken() async throws -> String {
    idToken
  }
}

func configureExternalAccountCredentials(
  idToken: String,
  regionalTokenURL: URL
) throws {
  let provider = CustomOIDCSubjectTokenProvider(idToken: idToken)
  let audience =
    "//iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/my-pool/providers/my-provider"

  // Uses https://sts.googleapis.com/v1/token automatically in the default universe:
  let defaultConfig = ExternalAccountConfig(
    credentialSource: .programmatic(subjectTokenProvider: provider),
    audience: audience,
    subjectTokenType: .idToken
  )
  _ = try Credentials(configuration: .externalAccount(defaultConfig))

  // In a custom universe, leaving tokenURL nil derives https://sts.<universeDomain>/v1/token:
  let customUniverseConfig = ExternalAccountConfig(
    credentialSource: .programmatic(subjectTokenProvider: provider),
    audience:
      "//iam.apis-tpclp.goog/projects/123456789/locations/global/workloadIdentityPools/my-pool/providers/my-provider",
    subjectTokenType: .idToken
  ).with {
    $0.universeDomain = "apis-tpclp.goog"
  }
  _ = try Credentials(configuration: .externalAccount(customUniverseConfig))

  // Override tokenURL explicitly when targeting a regional or Private Service Connect STS endpoint:
  let regionalConfig = ExternalAccountConfig(
    credentialSource: .programmatic(subjectTokenProvider: provider),
    audience: audience,
    subjectTokenType: .idToken
  ).with {
    $0.tokenURL = regionalTokenURL
  }
  _ = try Credentials(configuration: .externalAccount(regionalConfig))
}
// snippet.hide

@main
struct SnippetRunner {
  static func main() throws {
    guard let regionalURL = URL(string: "https://sts.us-central1.rep.googleapis.com/v1/token")
    else {
      return
    }
    try configureExternalAccountCredentials(
      idToken: "[placeholder]",
      regionalTokenURL: regionalURL
    )
  }
}
