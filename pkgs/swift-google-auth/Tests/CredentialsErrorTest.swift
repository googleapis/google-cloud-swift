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
    let anyError: any Error = got
    #expect(got.description == "Operation not supported: -- details here --")
    #expect(
      got.debugDescription
        == "CredentialsError.notSupported(\"-- details here --\"): Operation not supported: -- details here --"
    )
    #expect(String(reflecting: anyError) == got.debugDescription)
  }

  @Test func parseError() {
    let got = CredentialsError.parseError("-- details here --")
    let anyError: any Error = got
    #expect(got.description == "Configuration parse error: -- details here --")
    #expect(
      got.debugDescription
        == "CredentialsError.parseError(\"-- details here --\"): Configuration parse error: -- details here --"
    )
    #expect(String(reflecting: anyError) == got.debugDescription)
  }

  @Test func cannotFetchTokenDetails() {
    let underlyingError = CredentialsError.notSupported("--inner--")
    let got = CredentialsError.cannotFetchToken(
      message: "--message here--", underlyingError: underlyingError)
    let anyError: any Error = got
    #expect(got.description == "--message here--: Operation not supported: --inner--")
    #expect(
      got.debugDescription.hasPrefix("CredentialsError.cannotFetchToken: --message here--"),
      "\(got):\n\(got.debugDescription)")
    #expect(
      got.debugDescription.contains(String(reflecting: underlyingError)),
      "\(got):\n\(got.debugDescription)")
    #expect(String(reflecting: anyError) == got.debugDescription)
  }
}
