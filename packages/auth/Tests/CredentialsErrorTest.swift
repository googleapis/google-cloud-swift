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
import GoogleCloudAuth

@Suite struct CredentialsErrorTest {
  @Test func notSupported() {
    let got = CredentialsError.notSupported("-- details here --")
    #expect(
      got.debugDescription.contains("-- details here --"),
      "\(got):\n\(got.debugDescription)")
  }

  @Test func parseErrorLocalized() {
    let got = CredentialsError.parseError("-- details here --")
    #expect(
      got.debugDescription.contains("-- details here --"),
      "\(got):\n\(got.debugDescription)")
  }

  @Test func cannotFetchTokenDetails() {
    let source = CredentialsError.notSupported("--inner--")
    let got = CredentialsError.cannotFetchToken(adc: true, env: nil, source: source)
    #expect(
      got.debugDescription.contains("\(source)"),
      "\(got):\n\(got.debugDescription)")
  }

  @Test(arguments: [
    (true, String?.none, "to use `.adc()`"),
    (true, String?.none, "The GCE_METADATA_HOST environment variable is not set"),
    (false, String?.none, "to use `.mds()`"),
    (false, String?.none, "The GCE_METADATA_HOST environment variable is not set"),
    (true, "--env-value--", "GCE_METADATA_HOST environment variable is set to '--env-value--'"),
    (false, "--env-value--", "GCE_METADATA_HOST environment variable is set to '--env-value--'"),
  ]) func cannotFetchToken(adc: Bool, env: String?, want: String) {
    let source = CredentialsError.notSupported("--inner--")
    let got = CredentialsError.cannotFetchToken(adc: adc, env: env, source: source)
    #expect(
      got.debugDescription.contains(want),
      "expected `\(want)` in the localized message, got:\n\(got.debugDescription)")
  }
}
