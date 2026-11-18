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

  @Test func isRetryableClassification() async throws {
    struct CustomFailure: Error {}

    #expect(CredentialsError.notSupported("unsupported")._isRetryable == false)
    #expect(CredentialsError.parseError("invalid")._isRetryable == false)
    #expect(
      CredentialsError.cannotLoadFile(
        message: "missing", underlyingError: URLError(.fileDoesNotExist)
      )._isRetryable == false
    )
    #expect(CredentialsError.credentialsNotFound("none")._isRetryable == false)

    // External or custom error types wrapped in `.cannotFetchToken` are non-retryable.
    #expect(
      CredentialsError.cannotFetchToken(
        message: "custom error", underlyingError: CustomFailure()
      )._isRetryable == false
    )
    #expect(
      CredentialsError.cannotFetchToken(
        message: "url error from custom provider", underlyingError: URLError(.timedOut)
      )._isRetryable == false
    )
    #expect(
      CredentialsError.cannotFetchToken(
        message: "inner parse error", underlyingError: CredentialsError.parseError("mismatch")
      )._isRetryable == false
    )

    // Transient auth HTTP errors and nested transient CredentialsError values are retryable.
    let transient = CredentialsError.cannotFetchToken(
      message: "transient token failure",
      underlyingError: AuthHTTPError.transportError(URLError(.networkConnectionLost))
    )
    #expect(transient._isRetryable == true)
    let nestedTransient = CredentialsError.cannotFetchToken(
      message: "impersonation source failed",
      underlyingError: transient
    )
    #expect(nestedTransient._isRetryable == true)

    // Expired static access tokens are non-retryable.
    let expiredCreds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(token: "mock-token.expired", expirationDate: .distantPast)
      )
    )
    let expiredError = await #expect(throws: CredentialsError.self) {
      _ = try await expiredCreds.headers()
    }
    #expect(expiredError?._isRetryable == false)

    // Custom AccessTokenProvider errors are non-retryable unless forwarding a transient CredentialsError.
    struct FailingProvider: AccessTokenProvider {
      let error: any Error & Sendable
      func accessToken() async throws -> AccessToken {
        throw error
      }
    }
    let customErrorCreds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(provider: FailingProvider(error: URLError(.timedOut)))
      )
    )
    let customProviderError = await #expect(throws: CredentialsError.self) {
      _ = try await customErrorCreds.headers()
    }
    #expect(customProviderError?._isRetryable == false)

    let forwardedTransientCreds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(provider: FailingProvider(error: transient))
      )
    )
    let forwardedError = await #expect(throws: CredentialsError.self) {
      _ = try await forwardedTransientCreds.headers()
    }
    #expect(forwardedError?._isRetryable == true)
  }
}
