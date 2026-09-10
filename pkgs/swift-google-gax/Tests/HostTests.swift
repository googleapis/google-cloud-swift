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
@_spi(GoogleCloudInternal) @testable import GoogleCloudGax

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
}
