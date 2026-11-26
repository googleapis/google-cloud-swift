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

@_spi(GoogleCloudInternal) @testable import GoogleAuth

@Suite struct UniverseDomainTests {
  @Test func nonEmptyNormalization() {
    #expect(_UniverseDomain(nonEmpty: nil) == nil)
    #expect(_UniverseDomain(nonEmpty: "") == nil)

    let standard = _UniverseDomain(nonEmpty: "googleapis.com")
    #expect(standard == .default)
    #expect(standard?.isDefault == true)

    let custom = _UniverseDomain(nonEmpty: "apis-tpclp.goog")
    #expect(custom?.rawValue == "apis-tpclp.goog")
    #expect(custom?.isDefault == false)
    #expect(custom.map(String.init(describing:)) == "apis-tpclp.goog")
    #expect(custom.map(String.init(reflecting:)) == "_UniverseDomain(\"apis-tpclp.goog\")")
  }

  @Test func resolveCandidateChain() {
    #expect(_UniverseDomain.resolve(nil, "") == .default)
    #expect(
      _UniverseDomain.resolve("", "key.universe.com")
        == _UniverseDomain(nonEmpty: "key.universe.com"))
    #expect(
      _UniverseDomain.resolve("override.universe.com", "key.universe.com")
        == _UniverseDomain(nonEmpty: "override.universe.com")
    )
  }

  @Test func resolveFromEnvironmentPrecedence() {
    #expect(_UniverseDomain.resolve(configured: nil, environment: [:]) == .default)
    #expect(
      _UniverseDomain.resolve(
        configured: "",
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": ""]
      ) == .default
    )
    #expect(
      _UniverseDomain.resolve(
        configured: nil,
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
      ).rawValue == "env.universe.com"
    )
    #expect(
      _UniverseDomain.resolve(
        configured: "",
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
      ).rawValue == "env.universe.com"
    )
    #expect(
      _UniverseDomain.resolve(
        configured: "options.universe.com",
        environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
      ).rawValue == "options.universe.com"
    )
  }

  @Test func serviceURLConstructsValidEndpoints() throws {
    let custom = try #require(_UniverseDomain(nonEmpty: "apis-tpclp.goog"))
    let stsURL = try custom.serviceURL(service: "sts", path: "/v1/token")
    #expect(stsURL.absoluteString == "https://sts.apis-tpclp.goog/v1/token")

    let iamURL = try custom.serviceURL(
      service: "iamcredentials",
      path: "v1/projects/-/serviceAccounts/sa@proj.iam.gserviceaccount.com:generateAccessToken"
    )
    #expect(
      iamURL.absoluteString
        == "https://iamcredentials.apis-tpclp.goog/v1/projects/-/serviceAccounts/sa@proj.iam.gserviceaccount.com:generateAccessToken"
    )

    let encodedIamURL = try custom.serviceURL(
      service: "iamcredentials",
      path: "/v1/projects/-/serviceAccounts/sa%40proj.iam.gserviceaccount.com:generateAccessToken"
    )
    #expect(
      encodedIamURL.absoluteString
        == "https://iamcredentials.apis-tpclp.goog/v1/projects/-/serviceAccounts/sa%40proj.iam.gserviceaccount.com:generateAccessToken"
    )
  }

  @Test(arguments: [
    "evil.com:8443",
    "evil.com/extra",
    "evil.com%2Fextra",
    "user@evil.com",
    "evil.com?x=1",
    "evil.com#frag",
    "bad domain",
    "googleapis.com.",
    "..com",
    "evil.com,victim.com",
    "evil.com;param=1",
    "-evil.com",
    "evil-.com",
  ])
  func serviceURLRejectsMalformedUniverseDomain(malformed: String) throws {
    let domain = try #require(_UniverseDomain(nonEmpty: malformed))
    let error = #expect(throws: CredentialsError.self) {
      _ = try domain.serviceURL(service: "sts", path: "/v1/token")
    }
    guard case .parseError(let detail) = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(detail.contains("universe_domain"))
  }

  @Test(arguments: [
    "/v1/projects/-/serviceAccounts/sa|bad@proj.iam.gserviceaccount.com:generateAccessToken",
    "/v1/projects/-/serviceAccounts/sa%@proj.iam.gserviceaccount.com:generateAccessToken",
    "/v1/projects/-/serviceAccounts/sa@proj.iam.gserviceaccount.com:generateAccessToken?x=1",
    "/v1/projects/-/serviceAccounts/sa@proj.iam.gserviceaccount.com:generateAccessToken#frag",
  ])
  func serviceURLReportsInvalidPathSeparatelyFromUniverseDomain(badPath: String) throws {
    let error = #expect(throws: CredentialsError.self) {
      _ = try _UniverseDomain.default.serviceURL(service: "iamcredentials", path: badPath)
    }
    guard case .parseError(let detail) = error else {
      Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
      return
    }
    #expect(detail.contains("Invalid path"))
    #expect(!detail.contains("Invalid universe_domain"))
  }

  @Test func equalityIsExactCaseSensitive() throws {
    let custom = try #require(_UniverseDomain(nonEmpty: "my-universe.com"))
    let same = try #require(_UniverseDomain(nonEmpty: "my-universe.com"))
    let upper = try #require(_UniverseDomain(nonEmpty: "MY-UNIVERSE.COM"))

    #expect(custom == same)
    #expect(custom != upper)
    #expect(custom != .default)
  }

  @Test func validateServiceEndpointHostCoversAllPatternsAndEdgeCases() throws {
    let tpc = try #require(_UniverseDomain(nonEmpty: "apis-tpclp.goog"))
    let gdu = _UniverseDomain.default

    // Accepted hosts in custom universe (global, REP regional, purpose-regional, locational, PSC/custom proxy, loopback).
    for validTPCHost in [
      "sts.apis-tpclp.goog",
      "STS.apis-tpclp.goog",
      "STS.APIS-TPCLP.GOOG",
      "sts.us-central1.rep.apis-tpclp.goog",
      "STS.US-CENTRAL1.REP.apis-tpclp.goog",
      "content-sts.us-central1.rep.apis-tpclp.goog",
      "us-central1-sts.apis-tpclp.goog",
      "US-CENTRAL1-STS.apis-tpclp.goog",
      "US-CENTRAL1-STS.APIS-TPCLP.GOOG",
      "sts-psc.apis-tpclp.goog",
      "my-psc.p.apis-tpclp.goog",
      "private.apis-tpclp.goog",
      "PRIVATE.APIS-TPCLP.GOOG",
      "restricted.apis-tpclp.goog",
      "localhost",
      "127.0.0.1",
      "[::1]",
    ] {
      try tpc.validateServiceEndpointHost(validTPCHost, service: "sts", settingName: "token_url")
    }

    // Accepted hosts in default universe (including GDU regional `<service>.<region>.googleapis.com`).
    for validGDUHost in [
      "sts.googleapis.com",
      "STS.GOOGLEAPIS.COM",
      "sts.us-east1.googleapis.com",
      "sts.us-central1.rep.googleapis.com",
      "content-sts.us-central1.rep.googleapis.com",
      "us-central1-sts.googleapis.com",
      "private.googleapis.com",
      "my-psc.p.googleapis.com",
      "sts-proxy.corp.example.com",
    ] {
      try gdu.validateServiceEndpointHost(validGDUHost, service: "sts", settingName: "token_url")
    }

    // Rejected hosts in custom universe (including cross-universe gateways/PSC, non-STS universe services/buckets,
    // trailing DNS root dots, non-REP single-label regional, and Unicode case-folding edge cases).
    for rejectedTPCHost in [
      "",
      ".",
      "[]",
      "sts.googleapis.com",
      "sts.us-east1.apis-tpclp.goog",
      "sts..rep.apis-tpclp.goog",
      "content-sts.us-central1.rep.apis-s3ns.fr",
      "us-central1-sts.googleapis.com",
      "-sts.apis-tpclp.goog",
      "attacker-bucket.storage.apis-tpclp.goog",
      "storage.apis-tpclp.goog",
      "evil.sts.apis-tpclp.goog",
      "private.googleapis.com",
      "private.apis-s3ns.fr",
      "restricted.apis-s3ns.fr",
      "www.apis-s3ns.fr",
      "my-psc.p.apis-s3ns.fr",
      ".p.apis-tpclp.goog",
      "private.googleapis.com.",
      "sts-psc.googleapis.com...",
      "sts.mtls.apis-s3ns.fr",
      "googleapis.com.",
      "İ-sts.",
      "İ-sts.ğ",
      "İ-sts.aapis-tpclp.goog",
      "K-sts.googleapis.com",
    ] {
      #expect(throws: CredentialsError.self) {
        try tpc.validateServiceEndpointHost(
          rejectedTPCHost,
          service: "sts",
          settingName: "token_url"
        )
      }
    }

    // Rejected hosts in default universe (including cross-universe gateways/PSC, non-STS universe services/buckets,
    // trailing dots, & Unicode length shifts).
    for rejectedGDUHost in [
      "sts.apis-tpclp.goog",
      "sts.googleapis.com.",
      "us-central1-sts.apis-tpclp.goog",
      "us-central1-sts.googleapis.com.",
      "content-sts.us-central1.rep.apis-tpclp.goog",
      "attacker-bucket.storage.googleapis.com",
      "storage.googleapis.com",
      "evil.sts.googleapis.com",
      "private.apis-tpclp.goog",
      "restricted.apis-tpclp.goog",
      "www.apis-tpclp.goog",
      "my-psc.p.apis-tpclp.goog",
      "sts.mtls.apis-tpclp.goog",
      "-sts.googleapis.com",
      "İ-sts.ggoogleapis.com",
      "İ-sts.",
    ] {
      #expect(throws: CredentialsError.self) {
        try gdu.validateServiceEndpointHost(
          rejectedGDUHost,
          service: "sts",
          settingName: "token_url"
        )
      }
    }

    // Strict mode (`allowCustomHosts: false`) rejects third-party and non-service universe hosts
    // (such as `{bucket}.storage.<universe>` and `iamcredentials-psc.<universe>`) while allowing loopback & service hosts.
    try gdu.validateServiceEndpointHost(
      "localhost",
      service: "iamcredentials",
      settingName: "service_account_impersonation_url",
      allowCustomHosts: false
    )
    for rejectedStrictHost in [
      "attacker.example",
      "attacker-bucket.storage.googleapis.com",
      "storage.googleapis.com",
      "iamcredentials-psc.googleapis.com",
    ] {
      #expect(throws: CredentialsError.self) {
        try gdu.validateServiceEndpointHost(
          rejectedStrictHost,
          service: "iamcredentials",
          settingName: "service_account_impersonation_url",
          allowCustomHosts: false
        )
      }
    }
  }

  @Test func validateUniverseDomainMismatchIncludesDefaultUniverseHint() async throws {
    let creds = try Credentials(
      configuration: .accessToken(
        AccessTokenConfig(token: "tok").with { $0.universeDomain = "apis-tpclp.goog" }
      )
    )
    for invalidExpected in ["googleapis.com", ""] {
      let error = await #expect(throws: CredentialsError.self) {
        try await creds.validateUniverseDomain(invalidExpected)
      }
      guard let error, case let .parseError(detail) = error else {
        Issue.record("Expected CredentialsError.parseError, got \(String(describing: error))")
        return
      }
      #expect(
        detail.contains(
          "If you haven't configured the universe domain explicitly, `googleapis.com` is the default."
        )
      )
    }
  }

  @Test func resolveAndValidateServiceEndpointCoversOverridesAndStructuralChecks() throws {
    let tpc = try #require(_UniverseDomain(nonEmpty: "apis-tpclp.goog"))

    // `nil` override falls back to `serviceURL` with no `Host` override.
    let fallbackEndpoint = try tpc.resolveServiceEndpoint(
      override: nil,
      service: "sts",
      defaultPath: "/v1/token",
      settingName: "tokenURL"
    )
    #expect(fallbackEndpoint.url.absoluteString == "https://sts.apis-tpclp.goog/v1/token")
    #expect(fallbackEndpoint.hostHeader == nil)

    // Valid override with query allowed succeeds when `allowQuery: true`.
    let queryEndpoint = try tpc.resolveServiceEndpoint(
      override: "https://sts.apis-tpclp.goog/v1/token?foo=bar",
      service: "sts",
      defaultPath: "/v1/token",
      settingName: "tokenURL"
    )
    #expect(queryEndpoint.url.absoluteString == "https://sts.apis-tpclp.goog/v1/token?foo=bar")
    #expect(queryEndpoint.hostHeader == nil)

    // Shared gateway override returns `<service>.<universeDomain>` as `hostHeader`.
    let gatewayEndpoint = try tpc.validateServiceEndpoint(
      "https://private.apis-tpclp.goog/v1/token",
      service: "sts",
      settingName: "tokenURL"
    )
    #expect(gatewayEndpoint.url.absoluteString == "https://private.apis-tpclp.goog/v1/token")
    #expect(gatewayEndpoint.hostHeader == "sts.apis-tpclp.goog")

    // Query, root path, and empty bracketed host are rejected when `allowQuery: false` / `requireNonRootPath: true`.
    for rejectedIamURL in [
      "https://iamcredentials.apis-tpclp.goog",
      "https://iamcredentials.apis-tpclp.goog/",
      "https://iamcredentials.apis-tpclp.goog/v1/test?foo=bar",
      "https://[]/v1/test",
    ] {
      #expect(throws: CredentialsError.self) {
        _ = try tpc.validateServiceEndpoint(
          rejectedIamURL,
          service: "iamcredentials",
          settingName: "service_account_impersonation_url",
          requireNonRootPath: true,
          allowQuery: false
        )
      }
    }

    // Malformed `!isDefault` universe domains fail upfront in `validateServiceEndpoint` even when
    // the override URL targets loopback or a custom STS proxy.
    for malformedUniverse in [
      "googleapis.com.",
      "evil.com,victim.com",
      "-evil.com",
      "invalid/domain",
    ] {
      let badDomain = try #require(_UniverseDomain(nonEmpty: malformedUniverse))
      for overrideURL in [
        "https://localhost:8443/v1/token",
        "https://sts-proxy.corp.example.com/v1/token",
      ] {
        #expect(throws: CredentialsError.self) {
          _ = try badDomain.validateServiceEndpoint(
            overrideURL,
            service: "sts",
            settingName: "tokenURL"
          )
        }
      }
    }
  }
}
