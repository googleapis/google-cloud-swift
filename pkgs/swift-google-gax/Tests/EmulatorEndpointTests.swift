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
import GoogleAuth
import Testing
@_spi(GoogleCloudInternal) @testable import GoogleGax

@Suite struct EmulatorEndpointTests {
  @Test func ignoresEnvironmentWhenVariableNameIsNilOrEmpty() {
    let env = ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]

    let nilVar = _Host.resolveEmulatorEndpoint(
      endpoint: nil,
      emulatorEnvironmentVariable: nil,
      environment: env
    )
    #expect(nilVar.endpoint == nil)
    #expect(nilVar.isEmulator == false)

    let emptyVar = _Host.resolveEmulatorEndpoint(
      endpoint: nil,
      emulatorEnvironmentVariable: "",
      environment: env
    )
    #expect(emptyVar.endpoint == nil)
    #expect(emptyVar.isEmulator == false)
  }

  @Test func ignoresOtherEnvironmentVariables() {
    let resolved = _Host.resolveEmulatorEndpoint(
      endpoint: nil,
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["OTHER_EMULATOR_HOST": "127.0.0.1:9090"]
    )
    #expect(resolved.endpoint == nil)
    #expect(resolved.isEmulator == false)
  }

  @Test func ignoresWhitespaceOnlyEnvironmentValue() {
    let resolved = _Host.resolveEmulatorEndpoint(
      endpoint: nil,
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "   \t\n  "]
    )
    #expect(resolved.endpoint == nil)
    #expect(resolved.isEmulator == false)
  }

  @Test(arguments: [
    ("localhost:8085", "http://localhost:8085"),
    ("  127.0.0.1:8085  ", "http://127.0.0.1:8085"),
    ("[::1]:8085", "http://[::1]:8085"),
    ("http://localhost:8085", "http://localhost:8085"),
    ("https://localhost:8443", "https://localhost:8443"),
  ])
  func normalizesEmulatorHostValue(raw: String, expected: String) {
    let resolved = _Host.resolveEmulatorEndpoint(
      endpoint: nil,
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": raw]
    )
    #expect(resolved.endpoint == expected)
    #expect(resolved.isEmulator == true)
  }

  @Test func emptyEndpointFallsBackToEmulatorEnvironmentVariable() {
    let resolved = _Host.resolveEmulatorEndpoint(
      endpoint: "",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "localhost:8085"]
    )
    #expect(resolved.endpoint == "http://localhost:8085")
    #expect(resolved.isEmulator == true)
  }

  @Test func explicitEndpointOverridesEmulator() {
    let resolved = _Host.resolveEmulatorEndpoint(
      endpoint: "https://us-east1-example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]
    )
    #expect(resolved.endpoint == "https://us-east1-example.googleapis.com")
    #expect(resolved.isEmulator == false)
  }

  @Test func httpClientUsesAnonymousCredentialsForEmulator() async throws {
    let options = ClientOptions()
    let client = try _HTTPClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: [
        "EXAMPLE_EMULATOR_HOST": "localhost:8085",
        "NO_GCE_CHECK": "true",
        "GOOGLE_APPLICATION_CREDENTIALS": "/nonexistent/path/creds.json",
      ]
    )
    #expect(client.baseURL.scheme == "http")
    #expect(client.baseURL.host == "localhost")
    #expect(client.hostHeader == "localhost")
    #expect(client.baseURL.port == 8085)
    let authHeaders = try await client.credentials.headers()
    #expect(authHeaders.isEmpty)
  }

  @Test func httpClientPreservesExplicitCredentialsWithEmulator() async throws {
    let options = ClientOptions().with {
      $0.credentials = try? Credentials(configuration: .apiKey("custom-test-key"))
    }
    let client = try _HTTPClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "localhost:8085"]
    )
    #expect(client.baseURL.scheme == "http")
    #expect(client.baseURL.host == "localhost")
    #expect(client.baseURL.port == 8085)
    let authHeaders = try await client.credentials.headers()
    #expect(
      authHeaders.contains(where: { $0.name == "x-goog-api-key" && $0.value == "custom-test-key" }))
  }

  @Test func httpClientExplicitEndpointBeatsEmulator() async throws {
    let options = ClientOptions().with {
      $0.endpoint = "https://us-central1-example.googleapis.com"
      $0.credentials = try? Credentials(configuration: .anonymous)
    }
    let client = try _HTTPClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]
    )
    #expect(client.baseURL.scheme == "https")
    #expect(client.baseURL.host == "us-central1-example.googleapis.com")
    #expect(client.hostHeader == "us-central1-example.googleapis.com")
  }

  @Test func httpClientInvalidEmulatorEndpointThrowsInvalidEndpoint() {
    let options = ClientOptions()
    #expect(throws: ClientError.self) {
      _ = try _HTTPClient(
        from: options,
        withDefaultEndpoint: "https://example.googleapis.com",
        emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
        environment: ["EXAMPLE_EMULATOR_HOST": "ftp://localhost:8085"]
      )
    }
  }
}
