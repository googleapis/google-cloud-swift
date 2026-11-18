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

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import Testing
@_spi(GoogleCloudInternal) @testable import GoogleAuth

private struct MockSubjectTokenProvider: SubjectTokenProvider {
  let token: String

  func subjectToken() async throws -> String {
    return token
  }
}

private actor MockFailingSubjectTokenProvider: SubjectTokenProvider {
  struct ProviderError: Error {}

  let error: any Error
  var callCount = 0

  init(error: any Error = URLError(.networkConnectionLost)) {
    self.error = error
  }

  func subjectToken() async throws -> String {
    callCount = callCount + 1
    throw error
  }
}

@Suite struct ExternalAccountTests {
  @Test("Configures programmatic credentials with custom providers successfully")
  func createProgrammaticCredentials() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let clientAuth = ClientAuthentication(clientID: "client-id", clientSecret: "client-secret")
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience:
        "//iam.googleapis.com/projects/123/locations/global/workloadPools/pool/providers/prov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      clientAuthentication: clientAuth,
      workforcePoolUserProject: nil,
      scopes: ["scope1", "scope2"],
      universeDomain: "custom-universe.com"
    )

    #expect(
      creds.audience
        == "//iam.googleapis.com/projects/123/locations/global/workloadPools/pool/providers/prov")
    #expect(creds.subjectTokenType == "urn:ietf:params:oauth:token-type:id_token")
    #expect(creds.tokenURL == targetURL)
    #expect(creds.clientAuthentication == clientAuth)
    #expect(creds.workforcePoolUserProject == nil)
    #expect(creds.scopes == ["scope1", "scope2"])
    #expect(creds.universeDomain == "custom-universe.com")
  }

  @Test("Configures custom billing quota project programmatically")
  func createProgrammaticCredentialsWithQuotaProjectID() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "quota-project"
    )

    #expect(creds.workforcePoolUserProject == "quota-project")
  }

  @Test("Configures programmatic credentials universe domains correctly")
  func programmaticCredentialsWithUniverseDomain() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      universeDomain: "my-universe.com"
    )

    #expect(creds.universeDomain == "my-universe.com")
  }

  @Test("Validates missing programmatic fields throw error during initialization")
  func createProgrammaticCredentialsFailsOnMissingRequiredField() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    // Empty audience should throw parseError
    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: "",
        subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
        tokenURL: targetURL
      )
    }

    // Empty subjectTokenType should throw parseError
    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: "aud",
        subjectTokenType: "",
        tokenURL: targetURL
      )
    }
  }

  @Test("Enforces audience validation throwing error if workforce project is set on workload pools")
  func programmaticCredentialsWorkforcePoolUserProjectFailsWithoutWorkforcePoolAudience() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    // Non-workforce pool audience: starting with projects/ instead of locations/global/workforcePools/
    let workloadAudience =
      "//iam.googleapis.com/projects/123/locations/global/workloadPools/wpool/providers/wprov"

    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: workloadAudience,
        subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
        tokenURL: targetURL,
        workforcePoolUserProject: "billing-project"
      )
    }
  }

  @Test(
    "Accepts valid workforce pool audience formats",
    arguments: [
      "locations/global/workforcePools/pool/providers/provider",
      "//iam.googleapis.com/locations/global/workforcePools/pool/providers/provider",
      "//iam.apis-tpclp.goog/locations/global/workforcePools/pool/providers/provider",
      "//iam.my-universe.example.com/locations/global/workforcePools/pool/providers/provider",
      "//IAM.custom-universe.com/locations/global/workforcePools/pool/providers/provider",
    ]
  )
  func acceptsValidWorkforcePoolAudiences(audience: String) throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: audience,
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.apis-tpclp.goog/v1/token")!,
      workforcePoolUserProject: "billing-project",
      universeDomain: "apis-tpclp.goog"
    )
    #expect(creds.workforcePoolUserProject == "billing-project")
  }

  @Test(
    "Rejects invalid workforce pool audience formats",
    arguments: [
      "//iam.googleapis.com/locations/global/workforcePools/pool",
      "//iam.googleapis.com/locations/global/workforcePools/pool/providers/provider/extra",
      "//iam./locations/global/workforcePools/pool/providers/provider",
      "//iam.custom.com:8443/locations/global/workforcePools/pool/providers/provider",
      "//@iam.googleapis.com/locations/global/workforcePools/pool/providers/provider",
      "//sts.googleapis.com/locations/global/workforcePools/pool/providers/provider",
      "///locations/global/workforcePools/pool/providers/provider",
      "//iam.apis-tpclp.goog",
      "//iam.apis-tpclp.goog/projects/123/locations/global/workloadIdentityPools/pool/providers/provider",
      "/locations/global/workforcePools/pool/providers/provider",
      "locations:global/workforcePools/pool/providers/provider",
      "locations/global/workforcePools/pool/providers/prov?foo=bar",
      "locations/global/workforcePools/pool/providers/prov#frag",
    ]
  )
  func rejectsInvalidWorkforcePoolAudiences(audience: String) {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    #expect {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: audience,
        subjectTokenType: .idToken,
        tokenURL: targetURL,
        workforcePoolUserProject: "billing-project"
      )
    } throws: { error in
      guard case let CredentialsError.parseError(message) = error else {
        return false
      }
      return message.contains("workforcePoolUserProject")
    }
  }

  @Test("Validates authorization and billing quota headers match outgoing requirements")
  func programmaticCredentialsReturnsCorrectHeaders() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.fake-sts-access-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)
        #expect(request.headers["Content-Type"] == ["application/x-www-form-urlencoded"])

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData)),
        )
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "quota-project",
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer ya29.fake-sts-access-token")
    #expect(headers["x-goog-user-project"] == "quota-project")
  }

  @Test("Programmatic credentials retry correctly on transient errors")
  func programmaticCredentialsRetriesOnTransientFailures() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.success-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let busy = { @Sendable (request: HTTPClientRequest) in
      return HTTPClientResponse(version: .http2, status: .tooManyRequests)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: responseData)),
      )
    }
    let mock = MockHTTPClient([busy, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      retryConfiguration: retryConfig,
      httpClient: httpClient
    )

    // The call should succeed because the internal retry engine resolves it
    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer ya29.success-token")
  }

  @Test("Programmatic credentials do not retry on non-transient failures")
  func programmaticCredentialsDoesNotRetryOnNonTransientFailures() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        attempts.increment()
        // Permanent 403 error
        return HTTPClientResponse(version: .http2, status: .forbidden)
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    // First call throws the 403 error (permanent)
    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError1) = error1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is AuthHTTPError)
    #expect(attempts.getCount() == 1)

    // Second call should fail immediately WITHOUT calling the backend again (permanent error cached)
    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError2) = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(underlyingError2 is AuthHTTPError)
    #expect(attempts.getCount() == 1)
  }

  @Test("Programmatic credentials do not retry on malformed response")
  func programmaticCredentialsDoesNotRetryOnMalformedResponse() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let attempts = CallCounter()
    let malformedData = Data("invalid-json".utf8)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: malformedData))
        )
      }
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      retryConfiguration: retryConfig,
      httpClient: httpClient
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError1) = error1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is AuthHTTPError)
    #expect(attempts.getCount() == 1)

    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError2) = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(underlyingError2 is AuthHTTPError)
    #expect(attempts.getCount() == 1)
  }

  @Test("Programmatic credentials retry on transient network provider errors")
  func programmaticCredentialsRetriesOnProviderErrors() async throws {
    let provider = MockFailingSubjectTokenProvider(error: URLError(.networkConnectionLost))
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let mock = MockHTTPClient([])
    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    // First attempt wraps URLError in AuthHTTPError.transportError inside CredentialsError.cannotFetchToken
    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    let unwrapped1 = try #require(error1)
    #expect(unwrapped1._isRetryable == true)
    guard case let .cannotFetchToken(_, underlyingError1) = unwrapped1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect((underlyingError1 as? AuthHTTPError)?.urlError?.code == .networkConnectionLost)

    // Depending on how the TokenCache background task is scheduled, this count may be 1 or 2.
    let count1 = await provider.callCount
    #expect(count1 >= 1)

    // Since it's retryable, second attempt should call provider again
    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    let unwrapped2 = try #require(error2)
    #expect(unwrapped2._isRetryable == true)

    let count2 = await provider.callCount
    #expect(count2 > count1)
  }

  @Test(
    "Programmatic credentials fail fast on custom provider errors without poisoning TokenCache"
  )
  func programmaticCredentialsCustomProviderErrorFailsFastAndRecovers() async throws {
    actor RecoverableSubjectTokenProvider: SubjectTokenProvider {
      var callCount = 0
      var shouldFail = true

      func setShouldFail(_ value: Bool) {
        shouldFail = value
      }

      func subjectToken() async throws -> String {
        callCount += 1
        if shouldFail {
          throw HTTPClientError.remoteConnectionClosed
        }
        return "recovered-subject-token"
      }
    }

    let provider = RecoverableSubjectTokenProvider()
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let expectedResponse = TokenResponse(
      accessToken: "mock-token.sts-recovered",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { _ in
        HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    let unwrapped1 = try #require(error1)
    #expect(unwrapped1._isRetryable == false)
    guard case let .cannotFetchToken(_, underlyingError1) = unwrapped1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is HTTPClientError)
    #expect(await provider.callCount == 1)

    // Once the custom supplier recovers (e.g. after a Linux HTTPClientError blip), TokenCache
    // has not permanently latched the error and the next call succeeds.
    await provider.setShouldFail(false)
    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer mock-token.sts-recovered")
    #expect(await provider.callCount == 2)
  }

  @Test(
    "Programmatic credentials classify SubjectTokenProvider URLErrors via transient network allowlist",
    arguments: [
      (code: URLError.Code.timedOut, expectedRetryable: true),
      (code: .networkConnectionLost, expectedRetryable: true),
      (code: .cannotConnectToHost, expectedRetryable: true),
      (code: .notConnectedToInternet, expectedRetryable: true),
      (code: .dnsLookupFailed, expectedRetryable: true),
      (code: .cannotFindHost, expectedRetryable: true),
      (code: .cancelled, expectedRetryable: false),
      (code: .badURL, expectedRetryable: false),
      (code: .unsupportedURL, expectedRetryable: false),
      (code: .fileDoesNotExist, expectedRetryable: false),
      (code: .noPermissionsToReadFile, expectedRetryable: false),
      (code: .userAuthenticationRequired, expectedRetryable: false),
      (code: .serverCertificateUntrusted, expectedRetryable: false),
    ]
  )
  func programmaticCredentialsClassifiesSubjectTokenURLErrors(
    code: URLError.Code,
    expectedRetryable: Bool
  ) async throws {
    let provider = MockFailingSubjectTokenProvider(error: URLError(code))
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: AuthHTTPClient(mock: MockHTTPClient([]))
    )

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    let unwrapped = try #require(error)
    #expect(unwrapped._isRetryable == expectedRetryable)
  }

  @Test("Programmatic credentials cache permanent STS HTTP 4xx errors in TokenCache")
  func programmaticCredentialsCachesPermanentSTSError() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let stsAttempts = CallCounter()
    let mock = MockHTTPClient([
      { _ in
        stsAttempts.increment()
        return HTTPClientResponse(version: .http2, status: .badRequest)
      }
    ])
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: AuthHTTPClient(mock: mock)
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    #expect(error1?._isRetryable == false)
    #expect(stsAttempts.getCount() == 1)

    // Permanent STS 400 response is cached in TokenCache without re-contacting STS.
    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    #expect(error2?._isRetryable == false)
    #expect(stsAttempts.getCount() == 1)
  }

  @Test(
    "Successfully signs tokens and performs service account impersonation",
    .disabled("TODO(https://github.com/googleapis/google-cloud-swift/issues/86) - implement test"))
  func externalAccountWithImpersonationSuccess() async throws {}

  @Test("Successfully returns the direct STS access token when no impersonation is active")
  func externalAccountWithoutImpersonationSuccess() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.sts-direct-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData)),
        )
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer ya29.sts-direct-token")
  }

  @Test(
    "Constructs valid AccessTokenCredentials from programmatic configurations",
    .disabled("TODO(https://github.com/googleapis/google-cloud-swift/issues/86) - implement test"))
  func externalAccountAccessTokenCredentialsSuccess() async throws {}

  @Test(
    "Propagates transient errors when the STS endpoint fails with a 500",
    .disabled("TODO(https://github.com/googleapis/google-cloud-swift/issues/86) - implement test"))
  func impersonationFlowSTSCallFails() async throws {}

  @Test(
    "Immediately aborts and throws permanent errors on 403 Forbidden IAM exceptions",
    .disabled("TODO(https://github.com/googleapis/google-cloud-swift/issues/86) - implement test"))
  func impersonationFlowIAMCallFails() async throws {}

  @Test("Programmatic credentials recover successfully on transient retry conditions")
  func programmaticCredentialsRetriesForSuccess() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.success-after-retries",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let attempts = CallCounter()

    let unavailable = { @Sendable (request: HTTPClientRequest) in
      attempts.increment()
      return HTTPClientResponse(version: .http2, status: .serviceUnavailable)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      attempts.increment()
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: responseData)),
      )
    }
    let mock = MockHTTPClient([unavailable, unavailable, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      retryConfiguration: retryConfig,
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer ya29.success-after-retries")
    #expect(attempts.getCount() == 3)
  }

  @Test("Bypasses userProject options payload when client authentication is active")
  func stsHandlerIgnoresWorkforcePoolUserProjectWithClientAuth() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.sts-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) async throws in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        guard let buffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Request body is empty")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }

        let bodyString = (try buffer.getUTF8ValidatedString(at: 0, length: buffer.readableBytes))!
        let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        #expect(params["options"] == nil)
        #expect(
          request.headers["Authorization"] == ["Basic dGVzdC1jbGllbnQtaWQ6dGVzdC1jbGllbnQtc2VjcmV0"]
        )

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData)),
        )
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      clientAuthentication: ClientAuthentication(
        clientID: "test-client-id", clientSecret: "test-client-secret"),
      workforcePoolUserProject: "quota-project",
      httpClient: httpClient
    )

    _ = try await creds.headers()
  }

  @Test("Injects serialized userProject JSON options during token exchange form posts")
  func stsHandlerReceivesWorkforcePoolUserProject() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.sts-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.method == .POST)

        guard let buffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Request body is empty")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }

        let bodyString = (try buffer.getUTF8ValidatedString(at: 0, length: buffer.readableBytes))!
        let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        #expect(params["options"] == "{\"userProject\":\"quota-project\"}")

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData)),
        )
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "quota-project",
      httpClient: httpClient
    )

    _ = try await creds.headers()
  }

  @Test("Validates SubjectTokenType properties, constants, and codable support")
  func subjectTokenTypeBehavior() throws {
    typealias SubjectTokenType = ExternalAccountConfig.SubjectTokenType

    #expect(SubjectTokenType.idToken.rawValue == "urn:ietf:params:oauth:token-type:id_token")
    #expect(SubjectTokenType.jwt.rawValue == "urn:ietf:params:oauth:token-type:jwt")

    #expect(SubjectTokenType.idToken.description == "urn:ietf:params:oauth:token-type:id_token")
    #expect(SubjectTokenType.jwt.description == "urn:ietf:params:oauth:token-type:jwt")

    #expect(!SubjectTokenType.idToken.isEmpty)
    #expect(!SubjectTokenType.jwt.isEmpty)
    #expect(SubjectTokenType(rawValue: "").isEmpty)

    let literalToken: SubjectTokenType = "custom-token-type"
    #expect(literalToken.rawValue == "custom-token-type")
    #expect(!literalToken.isEmpty)

    let rawToken = SubjectTokenType(rawValue: "custom-token-type")
    #expect(literalToken == rawToken)

    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: MockSubjectTokenProvider(token: "token")),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    #expect(config.subjectTokenType == .idToken)
    #expect(config.subjectTokenType == "urn:ietf:params:oauth:token-type:id_token")

    let encoder = JSONEncoder()
    let data = try encoder.encode(SubjectTokenType.idToken)
    let decoded = try JSONDecoder().decode(SubjectTokenType.self, from: data)
    #expect(decoded == .idToken)
  }

  @Test("ClientAuthentication properties, equality, and hashing")
  func clientAuthenticationProperties() {
    let authWithSecret = ClientAuthentication(clientID: "my-id", clientSecret: "my-secret")
    #expect(authWithSecret.clientID == "my-id")
    #expect(authWithSecret.clientSecret == "my-secret")

    let authNoSecret = ClientAuthentication(clientID: "my-id")
    #expect(authNoSecret.clientID == "my-id")
    #expect(authNoSecret.clientSecret == nil)

    #expect(authWithSecret == ClientAuthentication(clientID: "my-id", clientSecret: "my-secret"))
    #expect(authWithSecret != authNoSecret)
    #expect(
      authWithSecret != ClientAuthentication(clientID: "other-id", clientSecret: "my-secret")
    )
    #expect(
      Set([authWithSecret, ClientAuthentication(clientID: "my-id", clientSecret: "my-secret")])
        .count == 1
    )
  }

  @Test(
    "ClientAuthentication descriptions redact clientSecret",
    arguments: ["super-secret-client-secret", "", nil] as [String?]
  )
  func clientAuthenticationDescriptionsRedactSecret(clientSecret: String?) {
    let auth = ClientAuthentication(clientID: "my-client-id", clientSecret: clientSecret)
    let expected = "ClientAuthentication(clientID: \"my-client-id\", clientSecret: \"[redacted]\")"
    #expect(String(describing: auth) == expected)
    #expect(String(reflecting: auth) == expected)
  }

  @Test("ExternalAccount configurations and credentials redact clientSecret in descriptions")
  func externalAccountContainersRedactClientSecret() throws {
    let clientAuth = ClientAuthentication(
      clientID: "my-client-id",
      clientSecret: "super-secret-client-secret"
    )
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(
        subjectTokenProvider: MockSubjectTokenProvider(token: "subj-token")
      ),
      audience: "//iam.googleapis.com/locations/global/workforcePools/pool/providers/prov",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    ).with {
      $0.clientAuthentication = clientAuth
    }
    let configuration = CredentialsConfiguration.externalAccount(config)
    let credentials = try Credentials(configuration: configuration)

    let formattedOutputs = [
      String(describing: config),
      String(reflecting: config),
      String(describing: configuration),
      String(reflecting: configuration),
      String(describing: credentials),
      String(reflecting: credentials),
    ]
    for output in formattedOutputs {
      #expect(!output.contains("super-secret-client-secret"))
      #expect(output.contains("my-client-id"))
      #expect(output.contains("[redacted]"))
    }
  }

  @Test("ExternalAccountConfig configures client authentication")
  func configWithClientAuthentication() throws {
    let provider = MockSubjectTokenProvider(token: "mock-token")
    let clientAuth = ClientAuthentication(clientID: "pool-client", clientSecret: "pool-secret")

    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/pool/providers/prov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    ).with {
      $0.clientAuthentication = clientAuth
    }

    #expect(config.clientAuthentication == clientAuth)

    let credentials = try Credentials(configuration: .externalAccount(config))
    guard let externalCreds = credentials.credentialsProvider as? ExternalAccountCredentials else {
      Issue.record("Expected ExternalAccountCredentials provider")
      return
    }
    #expect(externalCreds.clientAuthentication == clientAuth)
  }

  @Test("Injects Basic Auth header when client authentication has no secret")
  func stsHandlerInjectsBasicAuthWithoutSecret() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.sts-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let expectedBasicAuth = "Basic \(Data("test-client-id:".utf8).base64EncodedString())"

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == targetURL.absoluteString)
        #expect(request.headers.first(name: "Authorization") == expectedBasicAuth)

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData)),
        )
      }
    ])

    let httpClient = AuthHTTPClient(mock: mock)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      clientAuthentication: ClientAuthentication(clientID: "test-client-id"),
      httpClient: httpClient
    )

    _ = try await creds.headers()
    #expect(try await creds.universeDomain() == "googleapis.com")
  }

  @Test("ExternalAccountCredentials returns universeDomain")
  func universeDomainResolution() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      universeDomain: "custom.universe.com"
    )
    #expect(try await creds.universeDomain() == "custom.universe.com")

    let defaultCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL
    )
    #expect(try await defaultCreds.universeDomain() == "googleapis.com")

    let emptyCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      universeDomain: ""
    )
    #expect(try await emptyCreds.universeDomain() == "googleapis.com")
    try await emptyCreds.validateUniverseDomain("googleapis.com")

    let emptyConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: targetURL
    ).with {
      $0.universeDomain = ""
    }
    let publicCreds = try Credentials(configuration: .externalAccount(emptyConfig))
    #expect(try await publicCreds.universeDomain() == "googleapis.com")
    try await publicCreds.validateUniverseDomain("googleapis.com")
  }

  @Test("Normalizes empty workforcePoolUserProject to nil and omits STS options and header")
  func emptyWorkforcePoolUserProjectNormalizesToNil() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let expectedResponse = TokenResponse(
      accessToken: "ya29.sts-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let expectNoOptions: @Sendable (HTTPClientRequest) async throws -> HTTPClientResponse = {
      request in
      let buffer = try #require(try await request.body?.collect(upTo: 1024 * 1024))
      let bodyString = try #require(
        try buffer.getUTF8ValidatedString(at: 0, length: buffer.readableBytes))
      let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
      let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

      #expect(params["options"] == nil)

      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: responseData))
      )
    }
    let mock = MockHTTPClient([expectNoOptions, expectNoOptions])

    let httpClient = AuthHTTPClient(mock: mock)
    let workloadAudience =
      "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/wpool/providers/wprov"

    let workloadCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: workloadAudience,
      subjectTokenType: .idToken,
      tokenURL: targetURL,
      workforcePoolUserProject: "",
      httpClient: httpClient
    )
    #expect(workloadCreds.workforcePoolUserProject == nil)

    let headers = try await workloadCreds.headers()
    #expect(headers.count == 1)
    #expect(headers["Authorization"] == "Bearer ya29.sts-token")
    #expect(headers["x-goog-user-project"] == nil)

    let tokenProvider = ExternalAccountTokenProvider(
      subjectTokenProvider: provider,
      tokenURL: targetURL,
      subjectTokenType: .idToken,
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      scopes: [ExternalAccountConfig.defaultScope],
      workforcePoolUserProject: "",
      httpClient: httpClient
    )
    let token = try await tokenProvider.fetchToken()
    #expect(token.token == "ya29.sts-token")

    let workforceConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: .idToken,
      tokenURL: targetURL
    ).with {
      $0.workforcePoolUserProject = ""
    }
    let publicWorkforceCreds = try Credentials(configuration: .externalAccount(workforceConfig))
    let resolvedWorkforceProvider = try #require(
      publicWorkforceCreds.credentialsProvider as? ExternalAccountCredentials)
    #expect(resolvedWorkforceProvider.workforcePoolUserProject == nil)

    let workloadConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: workloadAudience,
      subjectTokenType: .idToken,
      tokenURL: targetURL
    ).with {
      $0.workforcePoolUserProject = ""
    }
    let publicWorkloadCreds = try Credentials(configuration: .externalAccount(workloadConfig))
    let resolvedWorkloadProvider = try #require(
      publicWorkloadCreds.credentialsProvider as? ExternalAccountCredentials)
    #expect(resolvedWorkloadProvider.workforcePoolUserProject == nil)
  }
}
