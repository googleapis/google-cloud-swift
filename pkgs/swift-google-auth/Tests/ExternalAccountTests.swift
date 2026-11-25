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
    let targetURL = URL(string: "https://sts.custom-universe.com/v1/token")!

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
    #expect(creds.universeDomain.rawValue == "custom-universe.com")
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
    let targetURL = URL(string: "https://sts.my-universe.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      universeDomain: "my-universe.com"
    )

    #expect(creds.universeDomain.rawValue == "my-universe.com")
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

    // First attempt wraps URLError inside CredentialsError.cannotFetchToken
    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    let unwrapped1 = try #require(error1)
    #expect(unwrapped1._isRetryable == true)
    guard case let .cannotFetchToken(_, underlyingError1) = unwrapped1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect((underlyingError1 as? URLError)?.code == .networkConnectionLost)

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
    "Programmatic credentials treat custom provider errors as retryable without poisoning TokenCache"
  )
  func programmaticCredentialsCustomProviderErrorRetriesAndRecovers() async throws {
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
    #expect(unwrapped1._isRetryable == true)
    #expect(AuthHTTPError.shouldCachePermanentError(unwrapped1) == false)
    guard case let .cannotFetchToken(_, underlyingError1) = unwrapped1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(underlyingError1 is HTTPClientError)
    #expect(await provider.callCount >= 1)

    // Once the custom supplier recovers (e.g. after a Linux HTTPClientError blip), TokenCache
    // has not permanently latched the error and the next call succeeds.
    await provider.setShouldFail(false)
    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer mock-token.sts-recovered")
    #expect(await provider.callCount >= 2)
  }

  @Test(
    "Programmatic credentials classify SubjectTokenProvider URLErrors",
    arguments: [
      (code: URLError.Code.timedOut, expectedDisposition: TokenErrorDisposition.retryable),
      (code: .networkConnectionLost, expectedDisposition: .retryable),
      (code: .cannotConnectToHost, expectedDisposition: .retryable),
      (code: .notConnectedToInternet, expectedDisposition: .retryable),
      (code: .dnsLookupFailed, expectedDisposition: .retryable),
      (code: .cannotFindHost, expectedDisposition: .retryable),
      (code: .secureConnectionFailed, expectedDisposition: .retryable),
      (code: .badServerResponse, expectedDisposition: .retryable),
      (code: .userAuthenticationRequired, expectedDisposition: .retryable),
      (code: .serverCertificateUntrusted, expectedDisposition: .retryable),
      (code: .cancelled, expectedDisposition: .uncached),
      (code: .badURL, expectedDisposition: .permanent),
      (code: .unsupportedURL, expectedDisposition: .permanent),
      (code: .fileDoesNotExist, expectedDisposition: .permanent),
      (code: .noPermissionsToReadFile, expectedDisposition: .permanent),
    ]
  )
  func programmaticCredentialsClassifiesSubjectTokenURLErrors(
    code: URLError.Code,
    expectedDisposition: TokenErrorDisposition
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
    #expect(unwrapped.errorDisposition == expectedDisposition)
    #expect(unwrapped._isRetryable == (expectedDisposition == .retryable))
    #expect(
      AuthHTTPError.shouldCachePermanentError(unwrapped) == (expectedDisposition == .permanent))
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

  @Test("Programmatic credentials cache permanent CredentialsError thrown by SubjectTokenProvider")
  func programmaticCredentialsCachesPermanentCredentialsErrorFromProvider() async throws {
    let provider = MockFailingSubjectTokenProvider(
      error: CredentialsError.parseError("Invalid nested credential configuration")
    )
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: AuthHTTPClient(mock: MockHTTPClient([]))
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    #expect(error1?._isRetryable == false)
    #expect(await provider.callCount == 1)

    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    #expect(error2?._isRetryable == false)
    #expect(await provider.callCount == 1)
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
    #expect(try await creds.universeDomain() == .default)
  }

  @Test("ExternalAccountCredentials returns universeDomain")
  func universeDomainResolution() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!
    let customURL = URL(string: "https://sts.custom.universe.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: customURL,
      universeDomain: "custom.universe.com"
    )
    #expect(try await creds.universeDomain().rawValue == "custom.universe.com")

    let defaultCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      environment: [:]
    )
    #expect(try await defaultCreds.universeDomain() == .default)

    let emptyCreds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      universeDomain: "",
      environment: [:]
    )
    #expect(try await emptyCreds.universeDomain() == .default)
    try await emptyCreds.validateUniverseDomain(.default)

    let emptyConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: targetURL
    ).with {
      $0.universeDomain = ""
    }
    let publicCreds = try Credentials(
      configuration: .externalAccount(emptyConfig),
      environment: [:]
    )
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

  enum TokenURLOverrideStyle: CaseIterable, Sendable {
    case initializer
    case withBuilder
    case propertyMutation
  }

  @Test("ExternalAccountConfig defaults tokenURL to nil and sends STS request to default universe")
  func configDefaultsTokenURLAndSendsRequest() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience:
        "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/p/providers/pr",
      subjectTokenType: .idToken
    )
    #expect(config.tokenURL == nil)

    let expectedResponse = TokenResponse(
      accessToken: "mock-default-url-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == "https://sts.googleapis.com/v1/token")
        #expect(request.method == .POST)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let credentials = try Credentials(
      externalAccount: config,
      httpClient: AuthHTTPClient(mock: mock),
      environment: [:]
    )
    #expect(try await credentials.universeDomain() == "googleapis.com")
    let headers = try await credentials.headers()
    #expect(headers["Authorization"] == "Bearer mock-default-url-token")
  }

  @Test("ExternalAccountConfig derives STS endpoint from universeDomain when tokenURL is nil")
  func configDerivesTokenURLFromUniverseDomain() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience:
        "//iam.apis-tpclp.goog/projects/123/locations/global/workloadIdentityPools/p/providers/pr",
      subjectTokenType: .idToken
    ).with {
      $0.universeDomain = "apis-tpclp.goog"
    }
    #expect(config.tokenURL == nil)

    let expectedResponse = TokenResponse(
      accessToken: "mock-universe-url-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == "https://sts.apis-tpclp.goog/v1/token")
        #expect(request.method == .POST)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let credentials = try Credentials(
      externalAccount: config,
      httpClient: AuthHTTPClient(mock: mock)
    )
    #expect(try await credentials.universeDomain() == "apis-tpclp.goog")
    let headers = try await credentials.headers()
    #expect(headers["Authorization"] == "Bearer mock-universe-url-token")
  }

  @Test(
    "ExternalAccountConfig rejects malformed universeDomain when deriving STS endpoint",
    arguments: [
      "evil.com:8443",
      "evil.com/extra",
      "user@evil.com",
      "evil.com?x=1",
      "evil.com#frag",
      "bad domain",
    ]
  )
  func configRejectsMalformedUniverseDomainWhenDerivingTokenURL(malformedUniverse: String) {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken
    ).with {
      $0.universeDomain = malformedUniverse
    }

    #expect {
      _ = try Credentials(configuration: .externalAccount(config))
    } throws: { error in
      guard case let CredentialsError.parseError(message) = error else {
        return false
      }
      return message.contains("universe_domain")
    }
  }

  @Test(
    "ExternalAccountConfig tokenURL override sends STS request to configured endpoint",
    arguments: TokenURLOverrideStyle.allCases
  )
  func configTokenURLOverrideSendsRequestToCustomEndpoint(style: TokenURLOverrideStyle) async throws
  {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let audience =
      "//iam.apis-tpclp.goog/projects/123/locations/global/workloadIdentityPools/p/providers/pr"
    let customURL = try #require(URL(string: "https://sts-psc.apis-tpclp.goog/v1/token"))

    let config: ExternalAccountConfig
    switch style {
    case .initializer:
      config = ExternalAccountConfig(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: audience,
        subjectTokenType: .idToken,
        tokenURL: customURL
      ).with {
        $0.universeDomain = "apis-tpclp.goog"
      }
    case .withBuilder:
      config = ExternalAccountConfig(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: audience,
        subjectTokenType: .idToken
      ).with {
        $0.tokenURL = customURL
        $0.universeDomain = "apis-tpclp.goog"
      }
    case .propertyMutation:
      var mutableConfig = ExternalAccountConfig(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: audience,
        subjectTokenType: .idToken
      )
      mutableConfig.tokenURL = customURL
      mutableConfig.universeDomain = "apis-tpclp.goog"
      config = mutableConfig
    }

    #expect(config.tokenURL == customURL)

    let expectedResponse = TokenResponse(
      accessToken: "mock-custom-url-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == customURL.absoluteString)
        #expect(request.method == .POST)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let credentials = try Credentials(
      externalAccount: config,
      httpClient: AuthHTTPClient(mock: mock)
    )
    #expect(try await credentials.universeDomain() == "apis-tpclp.goog")
    let headers = try await credentials.headers()
    #expect(headers["Authorization"] == "Bearer mock-custom-url-token")
  }

  @Test(
    "ExternalAccountConfig derives STS endpoint from GOOGLE_CLOUD_UNIVERSE_DOMAIN when universeDomain is unset"
  )
  func googleCloudUniverseDomainDerivesSTSEndpoint() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let config = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience:
        "//iam.apis-tpclp.goog/projects/123/locations/global/workloadIdentityPools/p/providers/pr",
      subjectTokenType: .idToken
    )
    let expectedResponse = TokenResponse(
      accessToken: "mock-env-universe-token",
      tokenType: "Bearer",
      expiresIn: 3600,
      issuedTokenType: "urn:ietf:params:oauth:token-type:access_token",
      refreshBy: nil
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(expectedResponse)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == "https://sts.apis-tpclp.goog/v1/token")
        #expect(request.method == .POST)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let credentials = try Credentials(
      externalAccount: config,
      httpClient: AuthHTTPClient(mock: mock),
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "apis-tpclp.goog"]
    )
    #expect(try await credentials.universeDomain() == "apis-tpclp.goog")
    let headers = try await credentials.headers()
    #expect(headers["Authorization"] == "Bearer mock-env-universe-token")
  }

  @Test(
    "ExternalAccountConfig validates explicit Google STS tokenURL against effective universe domain"
  )
  func explicitTokenURLValidatesAgainstUniverseDomain() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")

    // Default STS URL with GOOGLE_CLOUD_UNIVERSE_DOMAIN set to custom universe is rejected.
    let gduTokenConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .externalAccount(gduTokenConfig),
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "apis-tpclp.goog"]
      )
    }

    // Custom-universe STS URL with default universe (unset env & config) is rejected.
    let tpcTokenConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.apis-tpclp.goog/v1/token")!
    )
    #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .externalAccount(tpcTokenConfig),
        environment: [:]
      )
    }

    // `.googleapis.com` PSC/VPC-SC STS host under non-default universe is rejected.
    let gduPSCConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts-psc.googleapis.com/v1/token")!
    )
    #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .externalAccount(gduPSCConfig),
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "apis-tpclp.goog"]
      )
    }

    // Percent-encoded host in tokenURL is rejected.
    let encodedHostConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.apis-tpclp%2Egoog/v1/token")!
    )
    #expect(throws: CredentialsError.self) {
      _ = try Credentials(
        configuration: .externalAccount(encodedHostConfig),
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "apis-tpclp.goog"]
      )
    }

    // Regional and locational STS URLs matching effective universe succeed.
    for validURL in [
      "https://sts.us-central1.rep.apis-tpclp.goog/v1/token",
      "https://us-central1-sts.apis-tpclp.goog/v1/token",
    ] {
      let regionalConfig = ExternalAccountConfig(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: "aud",
        subjectTokenType: .idToken,
        tokenURL: URL(string: validURL)!
      )
      let creds = try Credentials(
        configuration: .externalAccount(regionalConfig),
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "apis-tpclp.goog"]
      )
      #expect(try await creds.universeDomain() == "apis-tpclp.goog")
    }

    // Regional GDU STS URL (`sts.<region>.googleapis.com`) succeeds in default universe.
    let regionalGDUConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.us-east1.googleapis.com/v1/token")!
    )
    let regionalGDUCreds = try Credentials(
      configuration: .externalAccount(regionalGDUConfig),
      environment: [:]
    )
    #expect(try await regionalGDUCreds.universeDomain() == "googleapis.com")
  }
}
