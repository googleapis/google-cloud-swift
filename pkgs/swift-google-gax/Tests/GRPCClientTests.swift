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
import GoogleCloudAuth
import GoogleCloudGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudGaxGRPC

@Suite struct GRPCClientTests {
  @Test func defaultEndpoint() throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with { $0.credentials = credentials }
    let client = try _GRPCClient(
      from: options, withDefaultEndpoint: "https://storage.googleapis.com")
    client.close()
  }

  @Test func customEndpoints() throws {
    let credentials = try Credentials(configuration: .anonymous)

    // With explicit https
    let secureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://custom.endpoint.com:443"
    }
    let secureClient = try _GRPCClient(
      from: secureOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    secureClient.close()

    // With explicit http (insecure emulator)
    let insecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "http://127.0.0.1:8080"
    }
    let insecureClient = try _GRPCClient(
      from: insecureOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    insecureClient.close()

    // Without scheme (auto https)
    let bareOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "custom.endpoint.com:443"
    }
    let bareClient = try _GRPCClient(
      from: bareOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    bareClient.close()

    // VPC-SC private endpoint
    let privateOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://private.googleapis.com"
    }
    let privateClient = try _GRPCClient(
      from: privateOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    privateClient.close()

    // Regional endpoint
    let regionalOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://storage.us-central1.rep.googleapis.com"
    }
    let regionalClient = try _GRPCClient(
      from: regionalOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    regionalClient.close()

    // Locational endpoint
    let locationalOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://us-central1-storage.googleapis.com"
    }
    let locationalClient = try _GRPCClient(
      from: locationalOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    locationalClient.close()

    // Universe domain
    let universeOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.universeDomain = "my-universe.com"
      $0.endpoint = "https://storage.my-universe.com"
    }
    let universeClient = try _GRPCClient(
      from: universeOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    universeClient.close()
  }

  @Test(arguments: [
    "",
    "http:///",
    "https:///",
  ]) func badEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = input
    }
    #expect(throws: ClientError.self) {
      let client = try _GRPCClient(
        from: options, withDefaultEndpoint: "https://storage.googleapis.com")
      client.close()
    }
  }
}
