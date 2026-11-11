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
@_spi(GoogleCloudInternal) @testable import GoogleGax

@Suite struct HostTests {
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
    ("localhost:5678", "localhost"),
    ("https://localhost:5678", "localhost"),
  ]) func headerSuccess(input: String, want: String) throws {
    let got = try _Host.header(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com"
    )
    #expect(got == want)
  }

  @Test(arguments: [
    ("https://service.googleapis.com", "service.googleapis.com"),
    ("http://service.googleapis.com", "service.googleapis.com"),
    ("https://storage.googleapis.com/", "storage.googleapis.com"),
    ("http://storage.googleapis.com/", "storage.googleapis.com"),
    ("test.googleapis.com", "test.googleapis.com"),
    ("localhost:5678", "localhost"),
    ("https://localhost:5678", "localhost"),
  ]) func headerDefault(input: String, want: String) throws {
    let got = try _Host.header(endpoint: nil, defaultEndpoint: input)
    #expect(got == want)
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
    let got = try _Host.header(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      universeDomain: "my-custom-universe.com"
    )
    #expect(got == want)
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
    let got = try _Host.authority(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com"
    )
    #expect(got == want)
  }

  @Test(arguments: [
    ("https://service.googleapis.com", "service.googleapis.com"),
    ("http://service.googleapis.com", "service.googleapis.com"),
    ("https://storage.googleapis.com/", "storage.googleapis.com"),
    ("http://storage.googleapis.com/", "storage.googleapis.com"),
    ("test.googleapis.com", "test.googleapis.com"),
    ("https://localhost:5678", "localhost:5678"),
    ("http://localhost:5678", "localhost:5678"),
  ]) func authorityDefault(input: String, want: String) throws {
    let got = try _Host.authority(endpoint: nil, defaultEndpoint: input)
    #expect(got == want)
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
    let got = try _Host.authority(
      endpoint: input,
      defaultEndpoint: "https://test.googleapis.com",
      universeDomain: "my-custom-universe.com"
    )
    #expect(got == want)
  }

  @Test func errors() {
    #expect(throws: ClientError.self) {
      _ = try _Host.header(
        endpoint: "https:///a/b/c",
        defaultEndpoint: "https://test.googleapis.com"
      )
    }

    #expect(throws: ClientError.self) {
      _ = try _Host.header(
        endpoint: "/a/b/c",
        defaultEndpoint: "https://test.googleapis.com"
      )
    }

    #expect(throws: ClientError.self) {
      _ = try _Host.header(
        endpoint: nil,
        defaultEndpoint: "https:///"
      )
    }
  }

  @Test func resolveUniverseDomainPrecedence() {
    let defaults = _Host.resolveUniverseDomain(options: ClientOptions(), environment: [:])
    #expect(defaults == "googleapis.com")

    let emptyFallback = _Host.resolveUniverseDomain(
      options: ClientOptions().with { $0.universeDomain = "" },
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": ""]
    )
    #expect(emptyFallback == "googleapis.com")

    let fromEnv = _Host.resolveUniverseDomain(
      options: ClientOptions(),
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromEnv == "env.universe.com")

    let options = ClientOptions().with { $0.universeDomain = "options.universe.com" }
    let fromOptions = _Host.resolveUniverseDomain(
      options: options,
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromOptions == "options.universe.com")
  }

  @Test func endpointResolutionWithUniverseDomain() throws {
    #expect(
      try _Host.endpoint(
        endpoint: nil,
        defaultEndpoint: "https://storage.googleapis.com",
        universeDomain: "googleapis.com"
      ) == "https://storage.googleapis.com"
    )
    #expect(
      try _Host.endpoint(
        endpoint: nil,
        defaultEndpoint: "https://storage.googleapis.com",
        universeDomain: "my-universe.com"
      ) == "https://storage.my-universe.com"
    )
    #expect(
      try _Host.endpoint(
        endpoint: nil,
        defaultEndpoint: "storage.googleapis.com",
        universeDomain: "my-universe.com"
      ) == "storage.my-universe.com"
    )
    #expect(
      try _Host.endpoint(
        endpoint: "https://custom.endpoint.com",
        defaultEndpoint: "https://storage.googleapis.com",
        universeDomain: "my-universe.com"
      ) == "https://custom.endpoint.com"
    )
    #expect(
      try _Host.endpoint(
        endpoint: nil,
        defaultEndpoint: "http://localhost:8080",
        universeDomain: "my-universe.com"
      ) == "http://localhost:8080"
    )
    let error = #expect(throws: ClientError.self) {
      _ = try _Host.endpoint(
        endpoint: nil,
        defaultEndpoint: "https://storage.googleapis.com",
        universeDomain: "invalid/domain"
      )
    }
    guard case .invalidEndpoint(let msg) = error else {
      Issue.record("Expected ClientError.invalidEndpoint, got \(String(describing: error))")
      return
    }
    #expect(msg == "storage.invalid/domain")
  }

  @Test(arguments: [
    // Default global endpoint -> global and regional upload hosts in same universe
    (
      endpoint: nil as String?,
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.googleapis.com"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://storage.us-central1.rep.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL:
        "https://storage.us-central1.rep.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.us-central1.rep.googleapis.com"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://us-central1-storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://us-central1-storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "us-central1-storage.googleapis.com"
    ),
    // Custom universe default endpoint -> global and regional upload hosts in custom universe
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://storage.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://storage.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.my-universe.com"
    ),
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://storage.us-central1.rep.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL:
        "https://storage.us-central1.rep.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.us-central1.rep.my-universe.com"
    ),
    // Regional endpoint -> matching regional upload host
    (
      endpoint: "https://storage.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.us-central1.rep.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL:
        "https://storage.us-central1.rep.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.us-central1.rep.googleapis.com"
    ),
    // VPC-SC / PSC endpoints -> rewrites connection target to baseURL, preserves target Host header
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1;part=2",
      wantURL: "https://private.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1%3Bpart=2",
      wantHost: "storage.googleapis.com"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://private.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://private.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.googleapis.com"
    ),
    (
      endpoint: "https://restricted.my-universe.com",
      universeDomain: "my-universe.com",
      uri: "https://storage.us-central1.rep.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://restricted.my-universe.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.us-central1.rep.my-universe.com"
    ),
    (
      endpoint: "https://my-psc.p.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantURL: "https://my-psc.p.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1",
      wantHost: "storage.googleapis.com"
    ),
    // Default port normalization & case-insensitive scheme/host
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "HTTPS://STORAGE.GOOGLEAPIS.COM:443/upload?upload_id=1",
      wantURL: "https://storage.googleapis.com/upload?upload_id=1",
      wantHost: "storage.googleapis.com"
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
    let defaultEndpoint = "https://storage.googleapis.com"
    let resolvedEndpoint = try _Host.endpoint(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    )
    let baseURL = try _HTTPClient.validateEndpoint(resolvedEndpoint)
    let defaultHostHeader = try _Host.header(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    )
    let result = try _Host.resolveRequestURI(
      uri,
      baseURL: baseURL,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain,
      defaultHostHeader: defaultHostHeader
    )
    #expect(result.components.url?.absoluteString == wantURL)
    #expect(result.hostHeader == wantHost)
  }

  @Test(arguments: [
    // Plaintext HTTP downgrade on HTTPS endpoints
    (
      endpoint: nil as String?,
      universeDomain: "googleapis.com",
      uri: "http://storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "http://storage.googleapis.com/upload?upload_id=1"
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
      uri: "https://storage.other-universe.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "my-universe.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://private.my-universe.com",
      universeDomain: "my-universe.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1"
    ),
    // Non-storage hosts in the same universe (other service, www, virtual-hosted bucket, other PSC)
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://secretmanager.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://www.googleapis.com/upload/storage/v1/b/bkt/o?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://my-bucket.storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://my-psc.p.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://other-psc.p.googleapis.com/upload?upload_id=1"
    ),
    // Regional client isolation (rejects global or other-region upload host)
    (
      endpoint: "https://storage.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.europe-west1.rep.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://storage.us-central1.rep.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1"
    ),
    // Custom endpoint host/port/scheme mismatches
    (
      endpoint: "https://my-proxy.example.com:8443",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1"
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
      uri: "https://storage.googleapis.com:8443/upload?upload_id=1"
    ),
    // Malformed, relative, non-HTTP, userinfo, fragment, double-slash, and percent-encoded/invalid-label URIs
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "/upload/storage/v1/b/bkt/o?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "ftp://storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://user:pass@storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1#frag"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com//evil.com/upload?upload_id=1"
    ),
    (
      endpoint: "http://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "https://private.googleapis.com",
      universeDomain: "googleapis.com",
      uri: "https://attacker.com%3A8080%2F-storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: nil,
      universeDomain: "googleapis.com",
      uri: "https://--storage.googleapis.com/upload?upload_id=1"
    ),
    (
      endpoint: "http://127.0.0.1:8080",
      universeDomain: "0.0.1",
      uri: "http://storage.0.0.1/upload?upload_id=1"
    ),
  ])
  func resolveRequestURIFailure(
    endpoint: String?,
    universeDomain: String,
    uri: String
  ) throws {
    let defaultEndpoint = "https://storage.googleapis.com"
    let resolvedEndpoint = try _Host.endpoint(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    )
    let baseURL = try _HTTPClient.validateEndpoint(resolvedEndpoint)
    let defaultHostHeader = try _Host.header(
      endpoint: endpoint,
      defaultEndpoint: defaultEndpoint,
      universeDomain: universeDomain
    )
    let error = #expect(throws: RequestError.self) {
      _ = try _Host.resolveRequestURI(
        uri,
        baseURL: baseURL,
        defaultEndpoint: defaultEndpoint,
        universeDomain: universeDomain,
        defaultHostHeader: defaultHostHeader
      )
    }
    guard case .badURL(let bad) = error else {
      Issue.record("Expected RequestError.badURL, got \(String(describing: error))")
      return
    }
    #expect(bad == uri)
  }
}
