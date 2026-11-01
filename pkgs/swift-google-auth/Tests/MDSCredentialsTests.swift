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
import NIOFoundationCompat
import NIOHTTP1
import Testing
@testable import GoogleAuth

@Suite struct MDSCredentialsTest {
  @Test func headersSuccessWithQuotaProject() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      quotaProjectID: "my-quota-project", client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
    #expect(
      headers["x-goog-user-project"] == "my-quota-project",
      "Missing quota project ID header in \(headers)"
    )
  }

  @Test func headersSuccessWithScopes() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        #expect(request.method == .GET)
        let url = URL(string: request.url)!
        #expect(url.path == "/computeMetadata/v1/instance/service-accounts/default/token")
        #expect(url.query == "scopes=scope1,scope2")
        #expect(request.headers["Metadata-Flavor"] == ["Google"])
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      scopes: ["scope1", "scope2"], client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func gceMetadataHostEnvVar() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(
      accessToken: "mock-override-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, environment: ["GCE_METADATA_HOST": "127.0.0.1:8080"])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-override-token",
      "Missing authorization header in \(headers) for overridden MDS host"
    )
  }

  @Test(arguments: [
    ("http-metadata-proxy.internal:8080", "http://http-metadata-proxy.internal:8080"),
    ("https-metadata-proxy.internal", "http://https-metadata-proxy.internal"),
    ("http://127.0.0.1:8080", "http://127.0.0.1:8080"),
    ("https://127.0.0.1:8443", "https://127.0.0.1:8443"),
    ("HTTP://127.0.0.1:8080", "HTTP://127.0.0.1:8080"),
    ("HTTPS://127.0.0.1:8443", "HTTPS://127.0.0.1:8443"),
    ("[::1]:8080", "http://[::1]:8080"),
  ])
  func gceMetadataHostSchemeAndPrefixResolution(hostEnv: String, expectedBase: String)
    async throws
  {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let mockPayload = MockResponse(
      accessToken: "mock-override-token", expiresIn: 3600, tokenType: "Bearer")
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(mockPayload)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        #expect(
          request.url
            == "\(expectedBase)/computeMetadata/v1/instance/service-accounts/default/token"
        )
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, environment: ["GCE_METADATA_HOST": hostEnv])
    let headers = try await provider.headers()

    #expect(headers["Authorization"] == "Bearer mock-override-token")
  }

  @Test(arguments: [
    "http://",
    "https://",
    "http://:8080",
    "127.0.0.1:abc",
    "::1",
    "ftp://127.0.0.1:8080",
    "http://invalid host with spaces",
    "invalid host with spaces",
    "://missing-scheme",
  ])
  func gceMetadataHostInvalidURLThrowsErrorWithoutCrash(invalidHost: String) async throws {
    // Pass an empty MockHTTPClient: its `deinit` asserts that all queued responses were consumed,
    // which verifies that invalid `GCE_METADATA_HOST` values fail before making any network calls.
    let mock = MockHTTPClient([])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, environment: ["GCE_METADATA_HOST": invalidHost])

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    guard let error, case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("Expected .cannotFetchToken, got \(String(describing: error))")
      return
    }
    guard case .parseError = underlyingError as? CredentialsError else {
      Issue.record(
        "Expected CredentialsError.parseError as underlyingError, got \(underlyingError)")
      return
    }
    #expect(AuthHTTPError.isRetryable(error) == false)
  }

  @Test func adcNoMDS() async throws {
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        throw URLError(.cannotConnectToHost)
      }
    ])
    let client = AuthHTTPClient(mock: mock)
    // Use zero jitter so any unintended background retry loop in `TokenCache` would fire
    // immediately and fail `MockHTTPClient` with an unqueued request.
    let provider = MDSCredentials(
      client: client,
      fromADC: true,
      environment: [:],
      jitter: { _ in .zero }
    )
    let error = await #expect(throws: CredentialsError.self) { _ = try await provider.headers() }

    guard case let .cannotFetchToken(got, _) = error else {
      Issue.record("Unexpected error type: \(error)")
      return
    }
    #expect(
      got.contains("Application Default Credentials"),
      "expected the ADC fallback explanation, got:\n\(got)")
    #expect(
      got.contains(MDSAccessTokenProvider.defaultEndpoint),
      "expected the default endpoint, got:\n\(got)")
    #expect(
      got.contains("gcloud auth application-default login"),
      "expected local credentials setup instructions, got:\n\(got)")
    #expect(mock.recordedTimeouts == [MDSAccessTokenProvider.adcFallbackTimeout])

    // Allow any background task opportunity to run; unconfirmed ADC fallback failure must be
    // treated as permanent so `TokenCache` neither polls in the background nor re-probes MDS.
    try await ContinuousClock().sleep(for: .milliseconds(20))
    await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    #expect(mock.recordedTimeouts == [MDSAccessTokenProvider.adcFallbackTimeout])
  }

  @Test func adcFallbackConfirmedOnSuccessUsesNormalTimeoutAndRetriesOnRefresh() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    // `expiresIn: -1` returns a token on the first `headers()` call that is already expired when
    // the second `headers()` call checks `TokenCache`, deterministically forcing a refresh.
    let initialData = try encoder.encode(
      MockResponse(accessToken: "initial-gcp-token", expiresIn: -1, tokenType: "Bearer")
    )
    let refreshedData = try encoder.encode(
      MockResponse(accessToken: "refreshed-gcp-token", expiresIn: 3600, tokenType: "Bearer")
    )

    let mock = MockHTTPClient([
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: initialData))
        )
      },
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(version: .http2, status: .serviceUnavailable)
      },
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: refreshedData))
        )
      },
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )
    let provider = MDSCredentials(
      retryConfiguration: retryConfig,
      client: AuthHTTPClient(mock: mock),
      fromADC: true,
      environment: [:],
      jitter: { _ in .seconds(3600) }
    )

    let firstHeaders = try await provider.headers()
    #expect(firstHeaders["Authorization"] == "Bearer initial-gcp-token")

    let secondHeaders = try await provider.headers()
    #expect(secondHeaders["Authorization"] == "Bearer refreshed-gcp-token")
    #expect(
      mock.recordedTimeouts == [
        MDSAccessTokenProvider.adcFallbackTimeout,
        AuthHTTPClient.defaultTimeout,
        AuthHTTPClient.defaultTimeout,
      ]
    )
  }

  @Test func adcFallbackTransientErrorWithMetadataFlavorHeaderConfirmsMDSAndRetries() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let recoveredData = try encoder.encode(
      MockResponse(accessToken: "boot-recovered-token", expiresIn: 3600, tokenType: "Bearer")
    )

    let mock = MockHTTPClient([
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .serviceUnavailable,
          headers: .init([("Metadata-Flavor", "Google")])
        )
      },
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([
            ("Content-Type", "application/json"),
            ("Metadata-Flavor", "Google"),
          ]),
          body: .bytes(.init(data: recoveredData))
        )
      },
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2,
      initialDelay: .milliseconds(1),
      multiplier: 1.0,
      maxDelay: .milliseconds(1)
    )
    let provider = MDSCredentials(
      retryConfiguration: retryConfig,
      client: AuthHTTPClient(mock: mock),
      fromADC: true,
      environment: [:]
    )

    let headers = try await provider.headers()
    #expect(headers["Authorization"] == "Bearer boot-recovered-token")
    #expect(
      mock.recordedTimeouts == [
        MDSAccessTokenProvider.adcFallbackTimeout,
        AuthHTTPClient.defaultTimeout,
      ]
    )
  }

  @Test func adcFallbackCancellationDoesNotPoisonTokenCache() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(
      MockResponse(accessToken: "post-cancel-token", expiresIn: 3600, tokenType: "Bearer")
    )

    let mock = MockHTTPClient([
      { request in
        Self.checkRequest(request)
        throw CancellationError()
      },
      { request in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      },
    ])

    let provider = MDSCredentials(
      client: AuthHTTPClient(mock: mock),
      fromADC: true,
      environment: [:]
    )

    await #expect(throws: CancellationError.self) {
      _ = try await provider.headers()
    }

    let headers = try await provider.headers()
    #expect(headers["Authorization"] == "Bearer post-cancel-token")
    #expect(
      mock.recordedTimeouts == [
        MDSAccessTokenProvider.adcFallbackTimeout,
        MDSAccessTokenProvider.adcFallbackTimeout,
      ]
    )
  }

  @Test func adcFallbackAndExplicitTimeoutSelection() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let encodedData = try encoder.encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    )
    let makeSuccess: MockHTTPClient.Closure = { request in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData))
      )
    }

    // 1. Implicit ADC fallback (`fromADC: true`, no custom endpoint, no `GCE_METADATA_HOST`) -> 3s
    let adcFallbackMock = MockHTTPClient([makeSuccess])
    let adcFallbackProvider = MDSCredentials(
      client: AuthHTTPClient(mock: adcFallbackMock),
      fromADC: true,
      environment: [:]
    )
    _ = try await adcFallbackProvider.headers()
    #expect(adcFallbackMock.recordedTimeouts == [.seconds(3)])

    // 2. Implicit ADC fallback with empty `GCE_METADATA_HOST` -> 3s
    let emptyHostMock = MockHTTPClient([makeSuccess])
    let emptyHostProvider = MDSCredentials(
      client: AuthHTTPClient(mock: emptyHostMock),
      fromADC: true,
      environment: ["GCE_METADATA_HOST": ""]
    )
    _ = try await emptyHostProvider.headers()
    #expect(emptyHostMock.recordedTimeouts == [.seconds(3)])

    // 3. Explicit `fromADC: false` -> default 30s
    let nonADCMock = MockHTTPClient([makeSuccess])
    let nonADCProvider = MDSCredentials(
      client: AuthHTTPClient(mock: nonADCMock),
      fromADC: false,
      environment: [:]
    )
    _ = try await nonADCProvider.headers()
    #expect(nonADCMock.recordedTimeouts == [.seconds(30)])

    // 4. `fromADC: true` with explicit `GCE_METADATA_HOST` -> default 30s
    let hostOverrideMock = MockHTTPClient([makeSuccess])
    let hostOverrideProvider = MDSCredentials(
      client: AuthHTTPClient(mock: hostOverrideMock),
      fromADC: true,
      environment: ["GCE_METADATA_HOST": "127.0.0.1:8080"]
    )
    _ = try await hostOverrideProvider.headers()
    #expect(hostOverrideMock.recordedTimeouts == [.seconds(30)])

    // 5. `fromADC: true` with explicit `endpoint` -> default 30s
    let endpointOverrideMock = MockHTTPClient([makeSuccess])
    let endpointOverrideProvider = MDSCredentials(
      endpoint: URL(string: "http://127.0.0.1:8080")!,
      client: AuthHTTPClient(mock: endpointOverrideMock),
      fromADC: true,
      environment: [:]
    )
    _ = try await endpointOverrideProvider.headers()
    #expect(endpointOverrideMock.recordedTimeouts == [.seconds(30)])
  }

  @Test func adcOverriddenMDS() async throws {
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        throw URLError(.cannotConnectToHost)
      }
    ])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client, fromADC: true, environment: ["GCE_METADATA_HOST": "127.0.0.1:1"])
    let credentialsError = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    let error = #expect(throws: AuthHTTPError.self) {
      if case let .cannotFetchToken(_, underlyingError) = credentialsError {
        throw underlyingError
      }
    }
    if case let .transportError(urlError) = error {
      #expect(
        urlError.code == .cannotConnectToHost, "Expected cannotConnectToHost, got \(urlError.code)")
    }
  }

  @Test func overriddenMDSErrorMessage() async throws {
    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        throw URLError(.cannotConnectToHost)
      }
    ])
    let client = AuthHTTPClient(mock: mock)
    let retryConfig = RetryConfiguration(
      maxAttempts: 1, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: true,
      environment: ["GCE_METADATA_HOST": "127.0.0.1:1"])
    let error = await #expect(throws: CredentialsError.self) { _ = try await provider.headers() }

    guard case let .cannotFetchToken(got, _) = error else {
      Issue.record("Unexpected error type: \(error)")
      return
    }
    #expect(
      got.contains("http://127.0.0.1:1"),
      "expected the overridden endpoint, got:\n\(got)")
    #expect(
      !got.contains("gcloud auth application-default login"),
      "expected no ADC fallback explanation for an explicit override, got:\n\(got)")
    #expect(
      !got.contains(".mds("),
      "expected no reference to a `.mds()` configuration, got:\n\(got)")
  }

  @Test func retriesOnTransientFailures() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encodedData = try JSONEncoder().encode(mockPayload)

    let unavailable = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: .serviceUnavailable)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([unavailable, unavailable, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func retriesForSuccess() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let internalError = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: .internalServerError)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([internalError, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func doesNotRetryOnNonTransientFailures() async throws {
    let attempts = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        let _ = attempts.increment()
        return HTTPClientResponse(version: .http2, status: .notFound, )
      }
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("expected a .cannotFetchToken error, got=\(error)")
      return
    }
    #expect(
      underlyingError is AuthHTTPError,
      "expected AuthHTTPError as the underlyingError, got \(underlyingError)")
    let count = attempts.getCount()
    #expect(count == 1, "Expected no retries on permanent HTTP 404 error, got \(count) calls")

    // Subsequent calls must throw the cached permanent error without contacting MDS again.
    await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    let secondCount = attempts.getCount()
    #expect(
      secondCount == 1,
      "Expected TokenCache to cache permanent HTTP 404 error, got \(secondCount) calls")
  }

  @Test(arguments: [
    (
      AuthHTTPError.unsuccessfulResponse(
        response: HTTPClientResponse(version: .http2, status: .notFound)),
      false
    ),
    (
      AuthHTTPError.unsuccessfulResponse(
        response: HTTPClientResponse(version: .http2, status: .forbidden)),
      false
    ),
    (
      AuthHTTPError.unsuccessfulResponse(
        response: HTTPClientResponse(version: .http2, status: .serviceUnavailable)),
      true
    ),
    (
      AuthHTTPError.transportError(URLError(.timedOut)),
      true
    ),
    (
      AuthHTTPError.decodingError(
        error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "corrupted"))),
      false
    ),
    (
      AuthHTTPError.invalidUTF8Response,
      false
    ),
  ])
  func isRetryableUnwrapsCredentialsError(underlyingError: AuthHTTPError, expected: Bool) {
    let wrapped = CredentialsError.cannotFetchToken(
      message: "failed", underlyingError: underlyingError)
    #expect(AuthHTTPError.isRetryable(wrapped) == expected)
  }

  @Test func doesNotRetryOnMalformedResponse() async throws {
    let attempts = CallCounter()
    let malformedData = Data("invalid-json".utf8)

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        let _ = attempts.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: malformedData))
        )
      }
    ])

    let retryConfig = RetryConfiguration(
      maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])

    let error = await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    guard case let .cannotFetchToken(_, underlyingError) = error else {
      Issue.record("expected a .cannotFetchToken error, got=\(error)")
      return
    }
    guard case .decodingError = underlyingError as? AuthHTTPError else {
      Issue.record(
        "expected AuthHTTPError.decodingError as the underlyingError, got \(underlyingError)")
      return
    }
    #expect(attempts.getCount() == 1, "Expected no retries on decoding error")

    await #expect(throws: CredentialsError.self) {
      _ = try await provider.headers()
    }
    #expect(attempts.getCount() == 1, "Expected TokenCache to cache permanent decoding error")
  }

  @Test func tokenCaching() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let networkCalls = CallCounter()

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        let _ = networkCalls.increment()
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData)),
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(client: client, environment: [:])

    _ = try await provider.headers()
    _ = try await provider.headers()
    _ = try await provider.headers()

    let count = networkCalls.getCount()
    #expect(
      count == 1, "Expected exactly 1 network request due to proactive actor caching, got \(count)")
  }

  @Test func retriesOnTransientNetworkErrors() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let timeout = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw URLError(.timedOut)
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }
    let mock = MockHTTPClient([timeout, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(retryConfiguration: retryConfig, client: client, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test(arguments: [
    HTTPResponseStatus.internalServerError,  // 500
    .notImplemented,  // 501
    .badGateway,  // 502
    .serviceUnavailable,  // 503
    .gatewayTimeout,  // 504
    .httpVersionNotSupported,  // 505
    .requestTimeout,  // 408
    .tooManyRequests,  // 429
  ])
  func retriesOnSpecificTransientStatusCodes(status: HTTPResponseStatus) async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let mockPayload = MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer")
    let encodedData = try JSONEncoder().encode(mockPayload)

    let failure = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: status)
    }
    let success = { @Sendable (request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([failure, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test(arguments: [
    HTTPResponseStatus.badRequest,  // 400
    .unauthorized,  // 401
    .forbidden,  // 403
    .notFound,  // 404
  ])
  func doesNotRetryOnSpecificNonTransientStatusCodes(status: HTTPResponseStatus) async throws {
    let failure = { @Sendable (_ request: HTTPClientRequest) in
      Self.checkRequest(request)
      return HTTPClientResponse(version: .http2, status: status)
    }
    let mock = MockHTTPClient([failure])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])

    await #expect(throws: (any Error).self) {
      _ = try await provider.headers()
    }
  }

  @Test func retriesOnConnectionReset() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let connectionReset = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw URLError(.networkConnectionLost)
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }

    let mock = MockHTTPClient([connectionReset, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func retriesOnIncompleteMessage() async throws {
    struct MockResponse: Encodable {
      let accessToken: String; let expiresIn: Int; let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let incompleteMessage = { @Sendable (request: HTTPClientRequest) throws -> HTTPClientResponse in
      Self.checkRequest(request)
      throw HTTPClientError.remoteConnectionClosed
    }
    let success = { @Sendable (request: HTTPClientRequest) throws in
      Self.checkRequest(request)
      return HTTPClientResponse(
        version: .http2,
        status: .ok,
        headers: .init([("Content-Type", "application/json")]),
        body: .bytes(.init(data: encodedData)),
      )
    }
    let mock = MockHTTPClient([incompleteMessage, success])

    let retryConfig = RetryConfiguration(
      maxAttempts: 2, initialDelay: .milliseconds(1), multiplier: 1.0, maxDelay: .milliseconds(1))
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      retryConfiguration: retryConfig, client: client, fromADC: false, environment: [:])
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func mdsCredentialsCustomJitter() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client,
      environment: [:],
      jitter: { range in
        return range.lowerBound
      }
    )
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  @Test func mdsCredentialsNilJitter() async throws {
    struct MockResponse: Encodable {
      let accessToken: String
      let expiresIn: Int
      let tokenType: String
    }
    let encodedData = try JSONEncoder().encode(
      MockResponse(accessToken: "mock-token", expiresIn: 3600, tokenType: "Bearer"))

    let mock = MockHTTPClient([
      { (request: HTTPClientRequest) in
        Self.checkRequest(request)
        return HTTPClientResponse(
          version: .http2,
          status: .ok,
          headers: .init([("Content-Type", "application/json")]),
          body: .bytes(.init(data: encodedData))
        )
      }
    ])

    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(
      client: client,
      environment: [:],
      jitter: nil
    )
    let headers = try await provider.headers()

    #expect(
      headers["Authorization"] == "Bearer mock-token",
      "Missing authorization header in \(headers)"
    )
  }

  /// Verifies that initializing `MDSCredentials` does not eagerly query the metadata server
  /// before `headers()` is called (`MockHTTPClient([])` asserts on `deinit` that no unexpected
  /// requests were made).
  @Test func mdsCredentialsInitDoesNotMakeNetworkRequests() async throws {
    let mock = MockHTTPClient([])
    let client = AuthHTTPClient(mock: mock)
    let provider = MDSCredentials(client: client, environment: [:])

    await Task.yield()
    _ = provider
  }

  static func checkRequest(
    _ request: HTTPClientRequest, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(request.method == .GET)
    let url = URL(string: request.url)!
    #expect(
      url.path == "/computeMetadata/v1/instance/service-accounts/default/token",
      sourceLocation: sourceLocation)
    #expect(request.headers["Metadata-Flavor"] == ["Google"], sourceLocation: sourceLocation)
  }
}
