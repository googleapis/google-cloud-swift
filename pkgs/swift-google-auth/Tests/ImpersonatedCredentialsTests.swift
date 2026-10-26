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

@testable import GoogleAuth

private struct StaticSourceCredentials: CredentialsProvider {
  let authHeaders: AuthHeaders

  func headers() async throws -> AuthHeaders {
    authHeaders
  }
}

private struct FailingSourceCredentials: CredentialsProvider {
  struct SourceError: Error {}

  func headers() async throws -> AuthHeaders {
    throw SourceError()
  }
}

@Suite struct ImpersonatedCredentialsTests {
  @Test func generatesAccessTokenWithDefaultParametersAndDelegates() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [
        ("Authorization", "Bearer source-access-token"),
        ("x-goog-user-project", "source-quota-project"),
      ]
    )

    let expectedURL =
      "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-impersonated-token",
      expireTime: "2099-01-01T01:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == expectedURL)
        #expect(request.method == .POST)
        #expect(request.headers["Authorization"] == ["Bearer source-access-token"])
        #expect(request.headers["x-goog-user-project"] == ["source-quota-project"])
        #expect(request.headers["Content-Type"] == ["application/json"])

        guard let bodyBuffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Expected HTTP request body")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }
        let bodyData = Data(buffer: bodyBuffer)
        let decodedBody = try JSONDecoder().decode(
          IAMGenerateAccessTokenRequest.self, from: bodyData)
        #expect(decodedBody.scope == ["https://www.googleapis.com/auth/cloud-platform"])
        #expect(
          decodedBody.delegates == [
            "projects/-/serviceAccounts/delegate1@project.iam.gserviceaccount.com",
            "projects/-/serviceAccounts/delegate2@project.iam.gserviceaccount.com",
          ]
        )
        #expect(decodedBody.lifetime == "3600s")

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      delegates: [
        "delegate1@project.iam.gserviceaccount.com",
        "projects/-/serviceAccounts/delegate2@project.iam.gserviceaccount.com",
      ],
      quotaProjectID: "impersonated-quota-project",
      httpClient: AuthHTTPClient(mock: mock),
      clock: TestClock()
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer mock-impersonated-token")
    #expect(headers["x-goog-user-project"] == "impersonated-quota-project")
  }

  @Test func customUniverseDomainScopesLifetimeAndResourceName() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [("Authorization", "Bearer source-token")]
    )

    let expectedURL =
      "https://iamcredentials.my-universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-custom-universe-token",
      expireTime: "2099-05-15T12:30:45.123456789Z"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)

    let mock = MockHTTPClient([
      { request in
        #expect(request.url == expectedURL)
        guard let bodyBuffer = try await request.body?.collect(upTo: 1024 * 1024) else {
          Issue.record("Expected HTTP request body")
          return HTTPClientResponse(version: .http2, status: .badRequest)
        }
        let bodyData = Data(buffer: bodyBuffer)
        let decodedBody = try JSONDecoder().decode(
          IAMGenerateAccessTokenRequest.self, from: bodyData)
        #expect(decodedBody.scope == ["scope1", "scope2"])
        #expect(decodedBody.delegates == nil)
        #expect(decodedBody.lifetime == "1800s")

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "projects/-/serviceAccounts/target@project.iam.gserviceaccount.com",
      scopes: ["scope1", "scope2"],
      lifetime: .seconds(1800),
      universeDomain: "my-universe.com",
      httpClient: AuthHTTPClient(mock: mock),
      clock: TestClock()
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer mock-custom-universe-token")
    #expect(headers["x-goog-user-project"] == nil)
  }

  @Test func cachesTokenAndPreventsDuplicateIAMCalls() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [("Authorization", "Bearer source-token")]
    )
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-cached-token",
      expireTime: "2099-01-01T01:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)
    let callCounter = CallCounter()

    let mock = MockHTTPClient([
      { _ in
        callCounter.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let clock = TestClock()
    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      clock: clock
    )

    let headers1 = try await creds.headers()
    await clock.sleeperWaiting()
    let headers2 = try await creds.headers()

    #expect(headers1["Authorization"] == "Bearer mock-cached-token")
    #expect(headers2["Authorization"] == "Bearer mock-cached-token")
    #expect(callCounter.getCount() == 1)
  }

  @Test func retriesTransientIAMErrorAndRecovers() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [("Authorization", "Bearer source-token")]
    )
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-recovered-token",
      expireTime: "2099-01-01T01:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { _ in
        attempts.increment()
        return HTTPClientResponse(version: .http2, status: .serviceUnavailable)
      },
      { _ in
        attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      },
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig,
      clock: TestClock()
    )

    let headers = try await creds.headers()
    #expect(headers["Authorization"] == "Bearer mock-recovered-token")
    #expect(attempts.getCount() == 2)
  }

  @Test func doesNotRetryPermanentIAMError() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [("Authorization", "Bearer source-token")]
    )
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { _ in
        attempts.increment()
        return HTTPClientResponse(version: .http2, status: .forbidden)
      }
    ])

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      clock: TestClock()
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
    guard case .cannotFetchToken = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(attempts.getCount() == 1)
  }

  @Test func propagatesSourceCredentialsError() async throws {
    let source = FailingSourceCredentials()
    let mock = MockHTTPClient([])

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      clock: TestClock()
    )

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case let .cannotFetchToken(message, underlyingError) = error else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error))")
      return
    }
    #expect(message.contains("source credentials"))
    #expect(underlyingError is FailingSourceCredentials.SourceError)
  }

  @Test func invalidExpireTimeThrowsNonRetryableCannotFetchToken() async throws {
    let source = StaticSourceCredentials(
      authHeaders: [("Authorization", "Bearer source-token")]
    )
    let responsePayload = IAMGenerateAccessTokenResponse(
      accessToken: "mock-bad-expiry",
      expireTime: "not-a-timestamp"
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let responseData = try encoder.encode(responsePayload)
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { _ in
        attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let creds = try ImpersonatedCredentialsGeneric(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      clock: TestClock()
    )

    let error1 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case .cannotFetchToken = error1 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error1))")
      return
    }
    #expect(attempts.getCount() == 1)

    let error2 = await #expect(throws: CredentialsError.self) {
      _ = try await creds.headers()
    }
    guard case .cannotFetchToken = error2 else {
      Issue.record("Expected CredentialsError.cannotFetchToken, got \(String(describing: error2))")
      return
    }
    #expect(attempts.getCount() == 1)
  }

  @Test func validationErrorsOnInit() throws {
    let source = StaticSourceCredentials(authHeaders: [])

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "../../other/path",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com?alt=media",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal:
          "projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:signBlob",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "projects//serviceAccounts/target@project.iam.gserviceaccount.com",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        delegates: [""],
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        universeDomain: "attacker.com/path#",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        lifetime: .seconds(0),
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        lifetime: .seconds(43_201),
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString: "not-a-valid-url",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString:
          "http://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString:
          "https://user:pass@iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString:
          "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken?alt=media",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString:
          "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken#frag",
        clock: TestClock()
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentialsGeneric(
        sourceCredentials: source,
        impersonationURLString: "https://iamcredentials.googleapis.com/",
        clock: TestClock()
      )
    }
  }

  @Test func parsesRFC3339TimestampsCorrectly() {
    let d1 = ImpersonatedTokenProvider.parseRFC3339Date("2026-10-26T20:00:00Z")
    #expect(d1 != nil)
    #expect(d1?.timeIntervalSince1970 == 1_793_044_800)

    let d2 = ImpersonatedTokenProvider.parseRFC3339Date("2026-10-26T20:00:00.5Z")
    #expect(d2 != nil)
    #expect(d2?.timeIntervalSince1970 == 1_793_044_800.5)

    let d3 = ImpersonatedTokenProvider.parseRFC3339Date("2026-10-26T22:00:00+02:00")
    #expect(d3 != nil)
    #expect(d3?.timeIntervalSince1970 == 1_793_044_800)

    #expect(ImpersonatedTokenProvider.parseRFC3339Date("invalid") == nil)
    #expect(ImpersonatedTokenProvider.parseRFC3339Date("0000-01-01T00:00:00Z") == nil)
    #expect(ImpersonatedTokenProvider.parseRFC3339Date("1969-12-31T23:59:59Z") == nil)
    #expect(ImpersonatedTokenProvider.parseRFC3339Date("2026-13-01T00:00:00Z") == nil)
    #expect(ImpersonatedTokenProvider.parseRFC3339Date("2026-02-29T00:00:00Z") == nil)
  }

  @Test func programmaticConfigurationConstructsImpersonatedCredentials() throws {
    let sourceCreds = try Credentials(configuration: .apiKey("source-key"))
    let config = ImpersonatedServiceAccountConfig(
      sourceCredentials: sourceCreds,
      targetPrincipal: "target@project.iam.gserviceaccount.com"
    ).with {
      $0.delegates = ["delegate@project.iam.gserviceaccount.com"]
      $0.scopes = ["https://www.googleapis.com/auth/devstorage.read_only"]
      $0.lifetime = .seconds(1800)
      $0.quotaProjectID = "billing-proj"
      $0.universeDomain = "custom.universe.com"
    }

    let credentials = try Credentials(configuration: .impersonatedServiceAccount(config))
    guard let impersonated = credentials.credentialsProvider as? ImpersonatedCredentials else {
      Issue.record("Expected ImpersonatedCredentials provider")
      return
    }

    #expect(impersonated.quotaProjectID == "billing-proj")
    #expect(impersonated.universeDomain == "custom.universe.com")
    #expect(
      impersonated.provider.iamEndpointURL.absoluteString
        == "https://iamcredentials.custom.universe.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
    )
    #expect(
      impersonated.provider.delegates == [
        "projects/-/serviceAccounts/delegate@project.iam.gserviceaccount.com"
      ]
    )
    #expect(
      impersonated.provider.scopes == ["https://www.googleapis.com/auth/devstorage.read_only"])
    #expect(impersonated.provider.lifetime == "1800s")
  }
}
