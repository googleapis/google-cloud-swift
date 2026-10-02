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

import Foundation
import Testing
import GoogleAuth

@Suite struct CredentialsErrorTest {
  @Test func notSupported() {
    let got = CredentialsError.notSupported("-- details here --")
    #expect(got.description == "Operation not supported: -- details here --")
    #expect(
      got.debugDescription.contains("-- details here --"),
      "\(got):\n\(got.debugDescription)")
    let localized = got as LocalizedError
    #expect(localized.errorDescription == got.description)
    #expect(
      localized.failureReason
        == "The requested credential type or feature is not supported (-- details here --)."
    )
    #expect(
      localized.recoverySuggestion
        == "Ensure the requested credential configuration is supported in the target environment or universe domain."
    )
    #expect(got.localizedDescription == got.description)
  }

  @Test func parseError() {
    let got = CredentialsError.parseError("-- details here --")
    #expect(got.description == "Configuration parse error: -- details here --")
    #expect(
      got.debugDescription.contains("-- details here --"),
      "\(got):\n\(got.debugDescription)")
    let localized = got as LocalizedError
    #expect(localized.errorDescription == got.description)
    #expect(
      localized.failureReason == "Failed to parse credentials data (-- details here --)."
    )
    #expect(
      localized.recoverySuggestion
        == "Check JSON key file formatting and ensure required fields like client_email and private_key are present."
    )
    #expect(got.localizedDescription == got.description)
  }

  @Test func cannotFetchTokenDetails() {
    let source = CredentialsError.notSupported("--inner--")
    let got = CredentialsError.cannotFetchToken(message: "--message here--", source: source)
    #expect(got.description == "--message here--: Operation not supported: --inner--")
    #expect(
      got.debugDescription.contains("--message here--"),
      "\(got):\n\(got.debugDescription)")
    #expect(
      got.debugDescription.contains("\(source)"),
      "\(got):\n\(got.debugDescription)")
    let localized = got as LocalizedError
    #expect(localized.errorDescription == got.description)
    #expect(localized.failureReason == "Operation not supported: --inner--")
    #expect(
      localized.recoverySuggestion
        == "Run 'gcloud auth application-default login' to set up local credentials, or verify Service Account / Workload Identity configuration."
    )
    #expect(got.localizedDescription == got.description)
  }
}
