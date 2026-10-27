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
import GoogleWKT
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
      expireTime: try #require(WKTTimestamp(rfc3339: "2099-01-01T01:00:00Z"))
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
        #expect(decodedBody.lifetime == (try WKTDuration(seconds: 3600)))

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      delegates: [
        "delegate1@project.iam.gserviceaccount.com",
        "projects/-/serviceAccounts/delegate2@project.iam.gserviceaccount.com",
      ],
      quotaProjectID: "impersonated-quota-project",
      httpClient: AuthHTTPClient(mock: mock)
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
      expireTime: try #require(WKTTimestamp(rfc3339: "2099-05-15T12:30:45.123456789Z"))
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
        #expect(decodedBody.lifetime == (try WKTDuration(seconds: 1800)))

        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: responseData))
        )
      }
    ])

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "projects/-/serviceAccounts/target@project.iam.gserviceaccount.com",
      scopes: ["scope1", "scope2"],
      lifetime: .seconds(1800),
      universeDomain: "my-universe.com",
      httpClient: AuthHTTPClient(mock: mock)
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
      expireTime: try #require(WKTTimestamp(rfc3339: "2099-01-01T01:00:00Z"))
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

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock)
    )

    let headers1 = try await creds.headers()
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
      expireTime: try #require(WKTTimestamp(rfc3339: "2099-01-01T01:00:00Z"))
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

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock),
      retryConfiguration: retryConfig
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

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock)
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

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock)
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
    let responseData = Data(
      #"{"access_token":"mock-bad-expiry","expire_time":"not-a-timestamp"}"#.utf8
    )
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

    let creds = try ImpersonatedCredentials(
      sourceCredentials: source,
      targetPrincipal: "target@project.iam.gserviceaccount.com",
      httpClient: AuthHTTPClient(mock: mock)
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
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: ""
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "../../other/path"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com?alt=media"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal:
          "projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:signBlob"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "projects//serviceAccounts/target@project.iam.gserviceaccount.com"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "."
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "projects/./serviceAccounts/target@project.iam.gserviceaccount.com"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "projects/-/serviceAccounts/."
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        delegates: [""]
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        universeDomain: "attacker.com/path#"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        lifetime: .seconds(0)
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        lifetime: .seconds(43_201)
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        targetPrincipal: "target@project.iam.gserviceaccount.com",
        lifetime: .seconds(43_200) + .milliseconds(500)
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString: "not-a-valid-url"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString:
          "http://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString:
          "https://user:pass@iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString:
          "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken?alt=media"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString:
          "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/target@project.iam.gserviceaccount.com:generateAccessToken#frag"
      )
    }

    #expect(throws: CredentialsError.self) {
      _ = try ImpersonatedCredentials(
        sourceCredentials: source,
        impersonationURLString: "https://iamcredentials.googleapis.com/"
      )
    }
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
    #expect(impersonated.provider.lifetime == (try WKTDuration(seconds: 1800)))
  }
}
