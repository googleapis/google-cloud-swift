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
@_spi(GoogleCloudInternal) @testable import GoogleAuth

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

  @Test func cannotLoadFileDetails() {
    let underlyingError = CredentialsError.notSupported("--inner--")
    let got = CredentialsError.cannotLoadFile(
      message: "--message here--", underlyingError: underlyingError)
    let anyError: any Error = got
    #expect(got.description == "--message here--: Operation not supported: --inner--")
    #expect(
      got.debugDescription.hasPrefix("CredentialsError.cannotLoadFile: --message here--"),
      "\(got):\n\(got.debugDescription)")
    #expect(
      got.debugDescription.contains(String(reflecting: underlyingError)),
      "\(got):\n\(got.debugDescription)")
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

  @Test func credentialsNotFound() {
    let got = CredentialsError.credentialsNotFound("-- details here --")
    let anyError: any Error = got
    #expect(got.description == "Credentials not found: -- details here --")
    #expect(
      got.debugDescription
        == "CredentialsError.credentialsNotFound(\"-- details here --\"): Credentials not found: -- details here --"
    )
    #expect(String(reflecting: anyError) == got.debugDescription)
  }

  private struct CustomFailure: Error {}

  @Test(arguments: [
    (CredentialsError.notSupported("unsupported"), false),
    (CredentialsError.parseError("invalid"), false),
    (
      CredentialsError.cannotLoadFile(
        message: "missing", underlyingError: URLError(.fileDoesNotExist)
      ),
      false
    ),
    (CredentialsError.credentialsNotFound("none"), false),
    (
      CredentialsError.cannotFetchToken(
        message: "cancelled", underlyingError: CancellationError()
      ),
      false
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "bad url", underlyingError: URLError(.badURL)
      ),
      false
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "inner parse error", underlyingError: CredentialsError.parseError("mismatch")
      ),
      false
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "custom error", underlyingError: CustomFailure()
      ),
      true
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "url error from custom provider", underlyingError: URLError(.timedOut)
      ),
      true
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "transient token failure",
        underlyingError: AuthHTTPError.transportError(URLError(.networkConnectionLost))
      ),
      true
    ),
    (
      CredentialsError.cannotFetchToken(
        message: "impersonation source failed",
        underlyingError: CredentialsError.cannotFetchToken(
          message: "transient token failure",
          underlyingError: AuthHTTPError.transportError(URLError(.networkConnectionLost))
        )
      ),
      true
    ),
  ])
  func isRetryableStaticCases(error: CredentialsError, expected: Bool) {
    #expect(error._isRetryable == expected)
  }

  @Test func expiredStaticAccessTokenIsNotRetryable() async throws {
    let expiredCreds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(token: "mock-token.expired", expirationDate: .distantPast)
      )
    )
    let expiredError = await #expect(throws: CredentialsError.self) {
      _ = try await expiredCreds.headers()
    }
    #expect(expiredError?._isRetryable == false)
  }

  @Test(arguments: [
    (CustomFailure() as any Error, true),
    (URLError(.timedOut) as any Error, true),
    (URLError(.badURL) as any Error, false),
    (CredentialsError.parseError("invalid") as any Error, false),
    (
      CredentialsError.cannotFetchToken(
        message: "transient token failure",
        underlyingError: AuthHTTPError.transportError(URLError(.networkConnectionLost))
      ) as any Error,
      true
    ),
  ])
  func customAccessTokenProviderRetryability(thrownError: any Error, expected: Bool) async throws {
    struct FailingProvider: AccessTokenProvider {
      let error: any Error
      func accessToken() async throws -> AccessToken {
        throw error
      }
    }
    let creds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(provider: FailingProvider(error: thrownError))
      )
    )
    let caughtError = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    #expect(caughtError?._isRetryable == expected)
  }
}
