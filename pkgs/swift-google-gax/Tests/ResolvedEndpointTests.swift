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

  @Test(arguments: [
    // Default global endpoint -> global and regional hosts in same universe
    (
      endpoint: nil as String?,
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://example.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "example.googleapis.com"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://example.us-central1.rep.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://example.us-central1.rep.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "example.us-central1.rep.googleapis.com"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://us-central1-example.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://us-central1-example.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "us-central1-example.googleapis.com"
    ),
    // Custom universe default endpoint -> global and regional hosts in custom universe
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://example.my-universe.com/upload/v1/items?upload_id=1",
      wantURL: "https://example.my-universe.com/upload/v1/items?upload_id=1",
      wantHost: "example.my-universe.com"
    ),
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://example.us-central1.rep.my-universe.com/upload/v1/items?upload_id=1",
      wantURL: "https://example.us-central1.rep.my-universe.com/upload/v1/items?upload_id=1",
      wantHost: "example.us-central1.rep.my-universe.com"
    ),
    // Regional endpoint -> matching regional host
    (
      endpoint: "https://example.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.us-central1.rep.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://example.us-central1.rep.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "example.us-central1.rep.googleapis.com"
    ),
    // VPC-SC / PSC endpoints -> rewrites connection target to baseURL, preserves target Host header
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload/v1/items?upload_id=1;part=2",
      wantURL: "https://private.googleapis.com/upload/v1/items?upload_id=1%3Bpart=2",
      wantHost: "example.googleapis.com"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://private.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://private.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "example.googleapis.com"
    ),
    (
      endpoint: "https://restricted.my-universe.com",
      universeDomain: "my-universe.com",
      uri: "https://example.us-central1.rep.my-universe.com/upload/v1/items?upload_id=1",
      wantURL: "https://restricted.my-universe.com/upload/v1/items?upload_id=1",
      wantHost: "example.us-central1.rep.my-universe.com"
    ),
    (
      endpoint: "https://my-psc.p.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload/v1/items?upload_id=1",
      wantURL: "https://my-psc.p.googleapis.com/upload/v1/items?upload_id=1",
      wantHost: "example.googleapis.com"
    ),
    // Default port normalization & case-insensitive scheme/host
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "HTTPS://EXAMPLE.GOOGLEAPIS.COM:443/upload?upload_id=1",
      wantURL: "https://example.googleapis.com/upload?upload_id=1",
      wantHost: "example.googleapis.com"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "HTTPS://EXAMPLE.US-CENTRAL1.REP.GOOGLEAPIS.COM:443/upload?upload_id=1",
      wantURL: "https://example.us-central1.rep.googleapis.com/upload?upload_id=1",
      wantHost: "example.us-central1.rep.googleapis.com"
    ),
    // Custom HTTPS proxy, HTTP localhost emulator, & IPv6 loopback emulator
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      uri: "https://MY-PROXY.EXAMPLE.COM:8443/upload?upload_id=1",
      wantURL: "https://my-proxy.example.com:8443/upload?upload_id=1",
      wantHost: "my-proxy.example.com"
    ),
    (
      endpoint: "http://localhost:8080",
      universeDomain: "googleapis.com",
      uri: "http://localhost:8080/upload?upload_id=1",
      wantURL: "http://localhost:8080/upload?upload_id=1",
      wantHost: "localhost"
    ),
    (
      endpoint: "http://[::1]:8080",
      universeDomain: "googleapis.com",
      uri: "http://[::1]:8080/upload?upload_id=1",
      wantURL: "http://[::1]:8080/upload?upload_id=1",
      wantHost: "[::1]"
    ),
  ])
  func resolveRequestURISuccess(
    endpoint: String?,
    universeDomain: String,
    uri: String,
    wantURL: String,
    wantHost: String
  ) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: endpoint,
      defaultEndpoint: "https://example.googleapis.com",
      universeDomain: _UniverseDomain.resolve(universeDomain)
    )
    let result = try resolved.resolveRequestURI(uri)
    #expect(result.components.url?.absoluteString == wantURL)
    #expect(result.hostHeader == wantHost)
  }

  @Test(arguments: [
    // Plaintext HTTP downgrade on HTTPS endpoints
    (
      endpoint: nil as String?,
      universeDomain: "googleapis.com",
      uri: "http://example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "http://example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      uri: "http://my-proxy.example.com:8443/upload?upload_id=1"
    ),
    // Cross-universe URIs
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://example.other-universe.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://private.my-universe.com",
      universeDomain: "my-universe.com",
      uri: "https://example.googleapis.com/upload?upload_id=1"
    ),
    // Non-matching hosts in the same universe (other service, www, subdomain, other PSC)
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://other-service.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://www.googleapis.com/upload/v1/items?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://sub.example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://my-psc.p.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://other-psc.p.googleapis.com/upload?upload_id=1"
    ),
    // Regional client isolation (rejects global or other-region host)
    (
      endpoint: "https://example.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.europe-west1.rep.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://example.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload?upload_id=1"
    ),
    // Custom endpoint host/port/scheme mismatches
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      uri: "https://my-proxy.example.com:9443/upload?upload_id=1"
    ),
    (
      endpoint: "http://localhost:8080",
      universeDomain: "googleapis.com",
      uri: "https://localhost:8080/upload?upload_id=1"
    ),
    // Non-default port on default/VPC-SC endpoint
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com:8443/upload?upload_id=1"
    ),
    // Malformed, relative, non-HTTP, userinfo, fragment, and empty-region URIs
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "/upload/v1/items?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "ftp://example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://user:pass@example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload?upload_id=1#frag"
    ),
    // Scheme mismatch (`https` session URI on an `http` endpoint)
    (
      endpoint: "http://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://example.googleapis.com/upload?upload_id=1"
    ),
    // Empty region labels in locational (`-<service>`) and regional (`.rep.`) hostnames
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://-example.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://example..rep.googleapis.com/upload?upload_id=1"
    ),
    // Case-sensitive `universeDomain` mismatch (`GOOGLEAPIS.COM` != `googleapis.com`)
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "GOOGLEAPIS.COM",
      uri: "https://example.us-central1.rep.googleapis.com/upload?upload_id=1"
    ),
  ])
  func resolveRequestURIFailure(
    endpoint: String?,
    universeDomain: String,
    uri: String
  ) throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: endpoint,
      defaultEndpoint: "https://example.googleapis.com",
      universeDomain: _UniverseDomain.resolve(universeDomain)
    )
    let error = #expect(throws: RequestError.self) {
      _ = try resolved.resolveRequestURI(uri)
    }
    guard case .badURL(let bad) = error else {
      Issue.record("Expected RequestError.badURL, got \(String(describing: error))")
      return
    }
    #expect(bad == uri)
  }

  @Test func resolveRequestURIClearsBaseURLQueryWhenSessionHasNoQuery() throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: "https://example.googleapis.com?leaked=1",
      defaultEndpoint: "https://example.googleapis.com"
    )
    let result = try resolved.resolveRequestURI("https://example.googleapis.com/upload/v1/items")
    #expect(result.components.percentEncodedQuery == nil)
    #expect(
      result.components.url?.absoluteString == "https://example.googleapis.com/upload/v1/items"
    )
  }

  @Test func customEndpointOverrideOnNonUniverseDefaultEndpointUsesCustomOrigin() throws {
    let resolved = try _ResolvedEndpoint(
      endpoint: "http://127.0.0.1:12345",
      defaultEndpoint: "https://localhost:7469"
    )
    #expect(resolved.service == nil)
    #expect(resolved.baseURL.string == "http://127.0.0.1:12345")
    #expect(resolved.host == "127.0.0.1")
    #expect(resolved.port == 12345)
    #expect(resolved.hostHeader == "127.0.0.1")
    #expect(resolved.authority == "127.0.0.1:12345")
  }
}
