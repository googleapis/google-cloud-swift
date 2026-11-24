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

@_spi(GoogleCloudInternal) import GoogleAuth
@_spi(GoogleCloudInternal) @testable import GoogleGax

@Suite struct ResolvedEndpointTests {
  @Test(arguments: [
    ("http://www.googleapis.com", "test.googleapis.com"),
    ("http://private.googleapis.com", "test.googleapis.com"),
    ("http://restricted.googleapis.com", "test.googleapis.com"),
    ("http://test-my-private-ep.p.googleapis.com", "test.googleapis.com"),
    ("https://us-central1-test.googleapis.com", "us-central1-test.googleapis.com"),
    ("https://us-central1-wrong.googleapis.com", "test.googleapis.com"),
    ("https://us-central1test.googleapis.com", "test.googleapis.com"),
    ("https://-test.googleapis.com", "test.googleapis.com"),
    ("https://test..rep.googleapis.com", "test.googleapis.com"),
    ("https://test.us-central1.rep.googleapis.com", "test.us-central1.rep.googleapis.com"),
    ("https://test.my-universe-domain.com", "test.my-universe-domain.com"),
    ("localhost:5678", "localhost"),
    ("https://localhost:5678", "localhost"),
  ]) func headerSuccess(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      allowsBareHost: true
    )
    #expect(resolved.hostHeader == want)
  }

  @Test(arguments: [
    ("https://service.googleapis.com", "service.googleapis.com"),
    ("http://service.googleapis.com", "service.googleapis.com"),
    ("https://example.googleapis.com/", "example.googleapis.com"),
    ("http://example.googleapis.com/", "example.googleapis.com"),
    ("test.googleapis.com", "test.googleapis.com"),
    ("localhost:5678", "localhost"),
    ("https://localhost:5678", "localhost"),
  ]) func headerDefault(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: input,
      allowsBareHost: true
    )
    #expect(resolved.hostHeader == want)
  }

  @Test(arguments: [
    ("http://www.my-custom-universe.com", "test.my-custom-universe.com"),
    ("https://test.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://private.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://restricted.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://test-my-private-ep.p.my-custom-universe.com", "test.my-custom-universe.com"),
    ("https://us-central1-test.my-custom-universe.com", "us-central1-test.my-custom-universe.com"),
    (
      "https://test.us-central1.rep.my-custom-universe.com",
      "test.us-central1.rep.my-custom-universe.com"
    ),
    ("https://www.googleapis.com", "test.googleapis.com"),
    ("https://private.googleapis.com", "test.googleapis.com"),
    ("https://restricted.googleapis.com", "test.googleapis.com"),
    ("https://test.googleapis.com", "test.googleapis.com"),
    ("https://us-central1-test.googleapis.com", "us-central1-test.googleapis.com"),
  ]) func headerUniverseDomain(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      universeDomain: _UniverseDomain.resolve("my-custom-universe.com"),
      allowsBareHost: true
    )
    #expect(resolved.hostHeader == want)
  }

  @Test(arguments: [
    ("http://www.googleapis.com", "test.googleapis.com"),
    ("http://private.googleapis.com", "test.googleapis.com"),
    ("http://restricted.googleapis.com", "test.googleapis.com"),
    ("http://test-my-private-ep.p.googleapis.com", "test.googleapis.com"),
    ("https://us-central1-test.googleapis.com", "us-central1-test.googleapis.com"),
    ("https://us-central1-wrong.googleapis.com", "test.googleapis.com"),
    ("https://us-central1test.googleapis.com", "test.googleapis.com"),
    ("https://-test.googleapis.com", "test.googleapis.com"),
    ("https://test.us-central1.rep.googleapis.com", "test.us-central1.rep.googleapis.com"),
    ("https://test.my-universe-domain.com", "test.my-universe-domain.com"),
    ("localhost:5678", "localhost:5678"),
    ("http://localhost:5678", "localhost:5678"),
  ]) func authoritySuccess(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      allowsBareHost: true
    )
    #expect(resolved.authority == want)
  }

  @Test(arguments: [
    ("https://service.googleapis.com", "service.googleapis.com"),
    ("http://service.googleapis.com", "service.googleapis.com"),
    ("https://example.googleapis.com/", "example.googleapis.com"),
    ("http://example.googleapis.com/", "example.googleapis.com"),
    ("test.googleapis.com", "test.googleapis.com"),
    ("https://localhost:5678", "localhost:5678"),
    ("http://localhost:5678", "localhost:5678"),
  ]) func authorityDefault(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: input,
      allowsBareHost: true
    )
    #expect(resolved.authority == want)
  }

  @Test(arguments: [
    ("http://www.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://private.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://restricted.my-custom-universe.com", "test.my-custom-universe.com"),
    ("http://test-my-private-ep.p.my-custom-universe.com", "test.my-custom-universe.com"),
    ("https://us-central1-test.my-custom-universe.com", "us-central1-test.my-custom-universe.com"),
    (
      "https://test.us-central1.rep.my-custom-universe.com",
      "test.us-central1.rep.my-custom-universe.com"
    ),
  ]) func authorityUniverseDomain(input: String, want: String) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      universeDomain: _UniverseDomain.resolve("my-custom-universe.com"),
      allowsBareHost: true
    )
    #expect(resolved.authority == want)
  }

  @Test func errors() {
    #expect(throws: ClientError.self) {
      _ = try _ResolvedEndpoint(
        endpoint: "https:///a/b/c",
        defaultEndpoint: "https://test.googleapis.com"
      )
    }

    #expect(throws: ClientError.self) {
      _ = try _ResolvedEndpoint(
        endpoint: "/a/b/c",
        defaultEndpoint: "https://test.googleapis.com",
        allowsBareHost: true
      )
    }

    #expect(throws: ClientError.self) {
      _ = try _ResolvedEndpoint(
        endpoint: "localhost:5678",
        defaultEndpoint: "https://test.googleapis.com",
        allowsBareHost: false
      )
    }

    #expect(throws: ClientError.self) {
      _ = try _ResolvedEndpoint(
        endpoint: nil,
        defaultEndpoint: "https:///"
      )
    }
  }

  @Test func resolveFromClientOptionsAndEnvironmentPrecedence() throws {
    let defaultResolved = try _ResolvedEndpoint(
      options: ClientOptions(),
      defaultEndpoint: "https://example.googleapis.com",
      environment: [:]
    )
    #expect(defaultResolved.universeDomain == .default)
    #expect(defaultResolved.baseURL.string == "https://example.googleapis.com")
    #expect(defaultResolved.service == "example")
    #expect(defaultResolved.isSecure == true)
    #expect(defaultResolved.port == 443)

    let emptyFallback = try _ResolvedEndpoint(
      options: ClientOptions().with { $0.universeDomain = "" },
      defaultEndpoint: "https://example.googleapis.com",
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": ""]
    )
    #expect(emptyFallback.universeDomain == .default)

    let fromEnv = try _ResolvedEndpoint(
      options: ClientOptions(),
      defaultEndpoint: "https://example.googleapis.com",
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromEnv.universeDomain.rawValue == "env.universe.com")
    #expect(fromEnv.baseURL.string == "https://example.env.universe.com")
    #expect(fromEnv.hostHeader == "example.env.universe.com")
    #expect(fromEnv.authority == "example.env.universe.com")

    let options = ClientOptions().with { $0.universeDomain = "options.universe.com" }
    let fromOptions = try _ResolvedEndpoint(
      options: options,
      defaultEndpoint: "https://example.googleapis.com",
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromOptions.universeDomain.rawValue == "options.universe.com")
    #expect(fromOptions.baseURL.string == "https://example.options.universe.com")
  }

  @Test func endpointResolutionWithUniverseDomain() throws {
    let defaultUniverse = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: "https://example.googleapis.com",
      universeDomain: .default
    )
    #expect(defaultUniverse.baseURL.string == "https://example.googleapis.com")

    let customUniverse = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: "https://example.googleapis.com",
      universeDomain: _UniverseDomain.resolve("my-universe.com")
    )
    #expect(customUniverse.baseURL.string == "https://example.my-universe.com")
    #expect(customUniverse.host == "example.my-universe.com")

    let bareHostUniverse = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: "example.googleapis.com",
      universeDomain: _UniverseDomain.resolve("my-universe.com"),
      allowsBareHost: true
    )
    #expect(bareHostUniverse.baseURL.string == "https://example.my-universe.com")
    #expect(bareHostUniverse.authority == "example.my-universe.com")

    let customOverride = try _ResolvedEndpoint(
      endpoint: "http://custom.endpoint.com",
      defaultEndpoint: "https://example.googleapis.com",
      universeDomain: _UniverseDomain.resolve("my-universe.com")
    )
    #expect(customOverride.baseURL.string == "http://custom.endpoint.com")
    #expect(customOverride.isSecure == false)
    #expect(customOverride.port == 80)

    let localhostDefault = try _ResolvedEndpoint(
      endpoint: nil,
      defaultEndpoint: "http://localhost:8080",
      universeDomain: _UniverseDomain.resolve("my-universe.com")
    )
    #expect(localhostDefault.baseURL.string == "http://localhost:8080")
    #expect(localhostDefault.service == nil)

    let error = #expect(throws: ClientError.self) {
      _ = try _ResolvedEndpoint(
        endpoint: nil,
        defaultEndpoint: "https://example.googleapis.com",
        universeDomain: _UniverseDomain.resolve("invalid/domain")
      )
    }
    guard case .invalidEndpoint(let msg) = error else {
      Issue.record("Expected ClientError.invalidEndpoint, got \(String(describing: error))")
      return
    }
    #expect(msg == "example.invalid/domain")
  }
}
