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
    _ = client.connection.close()
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
    _ = secureClient.connection.close()

    // With explicit http (insecure emulator)
    let insecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "http://127.0.0.1:8080"
    }
    let insecureClient = try _GRPCClient(
      from: insecureOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    _ = insecureClient.connection.close()

    // Without scheme (auto https)
    let bareOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "custom.endpoint.com:443"
    }
    let bareClient = try _GRPCClient(
      from: bareOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    _ = bareClient.connection.close()
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
      _ = client.connection.close()
    }
  }
}
