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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Testing

@testable import GoogleCloudAuth

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler:
    (@Sendable (URLRequest) throws -> (URLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let handler = MockURLProtocol.requestHandler else {
      fatalError("Handler is not set.")
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private struct MockSubjectTokenProvider: SubjectTokenProvider {
  let token: String

  func subjectToken() async throws -> String {
    return token
  }
}

private actor MockFailingSubjectTokenProvider: SubjectTokenProvider {
  struct ProviderError: Error {}

  var callCount = 0

  func subjectToken() async throws -> String {
    callCount = callCount + 1
    throw ProviderError()
  }
}

@Suite(.serialized)
struct ExternalAccountTests {
  private let mockSession: URLSession

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    self.mockSession = URLSession(configuration: config)
  }

  @Test("Configures programmatic credentials with custom providers successfully")
  func createProgrammaticCredentials() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience:
        "//iam.googleapis.com/projects/123/locations/global/workloadPools/pool/providers/prov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      clientID: "client-id",
      clientSecret: "client-secret",
      targetPrincipal: nil,
      workforcePoolUserProject: nil,
      scopes: ["scope1", "scope2"],
      universeDomain: "custom-universe.com"
    )

    #expect(
      creds.audience
        == "//iam.googleapis.com/projects/123/locations/global/workloadPools/pool/providers/prov")
    #expect(creds.subjectTokenType == "urn:ietf:params:oauth:token-type:id_token")
    #expect(creds.tokenURL == targetURL)
    #expect(creds.clientID == "client-id")
    #expect(creds.clientSecret == "client-secret")
    #expect(creds.targetPrincipal == nil)
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

  @Test("Throws notSupported error when targetPrincipal is provided")
  func createProgrammaticCredentialsFailsWhenImpersonationIsProvided() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: "aud",
        subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
        tokenURL: targetURL,
        targetPrincipal: "target-sa@project.iam.gserviceaccount.com"
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

  @Test("Validates workforce pool audience formats correctly")
  func workforcePoolAudienceValidation() throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    // 1. Valid audience without //iam.googleapis.com/ prefix
    _ = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "locations/global/workforcePools/pool/providers/provider",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "billing-project"
    )

    // 2. Valid audience with prefix
    _ = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/pool/providers/provider",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "billing-project"
    )

    // 3. Invalid audience: missing provider segment
    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience: "//iam.googleapis.com/locations/global/workforcePools/pool",
        subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
        tokenURL: targetURL,
        workforcePoolUserProject: "billing-project"
      )
    }

    // 4. Invalid audience: extra trailing segments
    #expect(throws: CredentialsError.self) {
      _ = try ExternalAccountCredentials(
        credentialSource: .programmatic(subjectTokenProvider: provider),
        audience:
          "//iam.googleapis.com/locations/global/workforcePools/pool/providers/provider/extra",
        subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
        tokenURL: targetURL,
        workforcePoolUserProject: "billing-project"
      )
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

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")
      #expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      workforcePoolUserProject: "quota-project",
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(
      headers.contains {
        $0.0 == "Authorization" && $0.1 == "Bearer ya29.fake-sts-access-token"
      })
    #expect(headers.contains { $0.0 == "X-Goog-User-Project" && $0.1 == "quota-project" })
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

    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { request in
      let attempt = attempts.increment()
      if attempt == 1 {
        // Fail with transient 429 error first
        let response = HTTPURLResponse(
          url: targetURL,
          statusCode: 429,
          httpVersion: nil,
          headerFields: [:]
        )!
        return (response, Data())
      } else {
        // Succeed on subsequent attempt
        let response = HTTPURLResponse(
          url: targetURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, responseData)
      }
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let httpClient = AuthHTTPClient(session: self.mockSession)
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
    #expect(headers.contains { $0.0 == "Authorization" && $0.1 == "Bearer ya29.success-token" })
    #expect(attempts.getCount() == 2)
  }

  @Test("Programmatic credentials do not retry on non-transient failures")
  func programmaticCredentialsDoesNotRetryOnNonTransientFailures() async throws {
    let provider = MockSubjectTokenProvider(token: "mock-provider-token")
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let attempts = CallCounter()

    MockURLProtocol.requestHandler = { request in
      attempts.increment()
      // Permanent 403 error
      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 403,
        httpVersion: nil,
        headerFields: [:]
      )!
      return (response, Data())
    }

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    // First call throws the 403 error (permanent)
    await #expect(throws: Error.self) {
      _ = try await creds.headers()
    }
    #expect(attempts.getCount() == 1)

    // Second call should fail immediately WITHOUT calling the backend again (permanent error cached)
    await #expect(throws: Error.self) {
      _ = try await creds.headers()
    }
    #expect(attempts.getCount() == 1)
  }

  @Test(
    "Programmatic credentials retry on custom provider errors",
    .disabled("TODO(https://github.com/googleapis/google-cloud-swift/issues/84) - the test flakes"))
  func programmaticCredentialsRetriesOnProviderErrors() async throws {
    let provider = MockFailingSubjectTokenProvider()
    let targetURL = URL(string: "https://sts.googleapis.com/v1/token")!

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    // First attempt should throw the provider error
    await #expect(throws: Error.self) {
      _ = try await creds.headers()
    }

    let count1 = await provider.callCount
    #expect(count1 == 1)

    // Since it's retryable, second attempt should call provider again
    await #expect(throws: Error.self) {
      _ = try await creds.headers()
    }

    let count2 = await provider.callCount
    #expect(count2 >= 2)
  }

  @Test("Successfully signs tokens and performs service account impersonation", .disabled("PR3"))
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

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(
      headers.contains {
        $0.0 == "Authorization" && $0.1 == "Bearer ya29.sts-direct-token"
      })
  }

  @Test(
    "Constructs valid AccessTokenCredentials from programmatic configurations", .disabled("PR3"))
  func externalAccountAccessTokenCredentialsSuccess() async throws {}

  @Test("Propagates transient errors when the STS endpoint fails with a 500", .disabled("PR3"))
  func impersonationFlowSTSCallFails() async throws {}

  @Test(
    "Immediately aborts and throws permanent errors on 403 Forbidden IAM exceptions",
    .disabled("PR3"))
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

    MockURLProtocol.requestHandler = { request in
      let attempt = attempts.increment()
      if attempt <= 2 {
        // Fail with transient 503 error for first two attempts
        let response = HTTPURLResponse(
          url: targetURL,
          statusCode: 503,
          httpVersion: nil,
          headerFields: [:]
        )!
        return (response, Data())
      } else {
        // Succeed on third attempt
        let response = HTTPURLResponse(
          url: targetURL,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!
        return (response, responseData)
      }
    }

    let retryConfig = RetryConfiguration(
      maxAttempts: 3,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "aud",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      retryConfiguration: retryConfig,
      httpClient: httpClient
    )

    let headers = try await creds.headers()
    #expect(
      headers.contains {
        $0.0 == "Authorization"
          && $0.1 == "Bearer ya29.success-after-retries"
      })
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

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")

      guard let bodyData = request.httpBody,
        let bodyString = String(data: bodyData, encoding: .utf8)
      else {
        Issue.record("Request body is empty")
        let errResponse = HTTPURLResponse(
          url: targetURL,
          statusCode: 400,
          httpVersion: nil,
          headerFields: nil
        )!
        return (errResponse, Data())
      }

      let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
      let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

      #expect(params["options"] == nil)
      let expectedAuth =
        "Basic dGVzdC1jbGllbnQtaWQ6dGVzdC1jbGllbnQtc2VjcmV0"
      #expect(request.value(forHTTPHeaderField: "Authorization") == expectedAuth)

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    let httpClient = AuthHTTPClient(session: self.mockSession)
    let creds = try ExternalAccountCredentials(
      credentialSource: .programmatic(subjectTokenProvider: provider),
      audience: "//iam.googleapis.com/locations/global/workforcePools/wpool/providers/wprov",
      subjectTokenType: "urn:ietf:params:oauth:token-type:id_token",
      tokenURL: targetURL,
      clientID: "test-client-id",
      clientSecret: "test-client-secret",
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

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == targetURL)
      #expect(request.httpMethod == "POST")

      guard let bodyData = request.httpBody,
        let bodyString = String(data: bodyData, encoding: .utf8)
      else {
        Issue.record("Request body is empty")
        let errResponse = HTTPURLResponse(
          url: targetURL,
          statusCode: 400,
          httpVersion: nil,
          headerFields: nil
        )!
        return (errResponse, Data())
      }

      let queryItems = URLComponents(string: "?" + bodyString)?.queryItems ?? []
      let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

      #expect(params["options"] == "{\"userProject\":\"quota-project\"}")

      let response = HTTPURLResponse(
        url: targetURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }

    let httpClient = AuthHTTPClient(session: self.mockSession)
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
}
