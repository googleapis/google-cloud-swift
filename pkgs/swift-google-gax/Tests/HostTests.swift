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

  @Test func resolveUniverseDomainPrecedenceAndValidation() throws {
    let defaults = try _Host.resolveUniverseDomain(options: ClientOptions(), environment: [:])
    #expect(defaults == "googleapis.com")

    let fromEnv = try _Host.resolveUniverseDomain(
      options: ClientOptions(),
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromEnv == "env.universe.com")

    let options = ClientOptions().with { $0.universeDomain = "options.universe.com" }
    let fromOptions = try _Host.resolveUniverseDomain(
      options: options,
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"]
    )
    #expect(fromOptions == "options.universe.com")

    for invalid in [
      "",
      "   ",
      ".",
      "..",
      ".googleapis.com",
      "googleapis.com.",
      "googleapis..com",
      "-googleapis.com",
      "googleapis-.com",
      "https://domain.com",
      "domain.com:443",
      "domain.com/path",
      "a?b",
      "evil.com%23",
    ] {
      #expect(throws: ClientError.self) {
        _ = try _Host.resolveUniverseDomain(
          options: ClientOptions().with { $0.universeDomain = invalid },
          environment: [:]
        )
      }
      #expect(throws: ClientError.self) {
        _ = try _Host.resolveUniverseDomain(
          options: ClientOptions(),
          environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": invalid]
        )
      }
    }
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
  }
}
