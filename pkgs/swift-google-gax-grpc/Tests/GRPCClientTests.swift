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
import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleGaxGRPC

@Suite struct GRPCClientTests {
  @Test func grpcTypealiasCompatibility() {
    let segment: GoogleGaxGRPC._RoutingSegment = .literal("test")
    #expect(segment == GoogleGax._RoutingSegment.literal("test"))
    #expect(GoogleGaxGRPC._RoutingMatcher.encode("foo/bar") == "foo%2Fbar")
  }

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

    // Custom domain endpoint
    let customDomainOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "https://storage.my-universe.com"
    }
    let customDomainClient = try _GRPCClient(
      from: customDomainOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    customDomainClient.close()

    // Case-insensitive scheme (HTTPS / HTTP)
    let upperSecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "HTTPS://custom.endpoint.com:443"
    }
    let upperSecureClient = try _GRPCClient(
      from: upperSecureOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    upperSecureClient.close()

    let upperInsecureOptions = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = "HTTP://127.0.0.1:8080"
    }
    let upperInsecureClient = try _GRPCClient(
      from: upperInsecureOptions, withDefaultEndpoint: "https://storage.googleapis.com")
    upperInsecureClient.close()
  }

  @Test(arguments: [
    "",
    "http:///",
    "https:///",
    "htps://storage.googleapis.com",
    "htt://localhost:1",
    "grpc://storage.googleapis.com",
    "dns:///storage.googleapis.com",
    "dns://8.8.8.8/storage.googleapis.com",
    "file:///etc/passwd",
    "ftp://storage.googleapis.com",
    "://storage.googleapis.com",
  ]) func badEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
      $0.endpoint = input
    }
    let error = #expect(throws: ClientError.self) {
      let client = try _GRPCClient(
        from: options, withDefaultEndpoint: "https://storage.googleapis.com")
      client.close()
    }
    guard case let .invalidEndpoint(msg) = error else {
      Issue.record(
        "Mismatched error type, want .invalidEndpoint, got=\(String(describing: error)).")
      return
    }
    #expect(msg == input, "error=\(String(describing: error))")
  }

  @Test(arguments: [
    "",
    "http:///",
    "https:///",
    "htps://storage.googleapis.com",
    "htt://localhost:1",
    "grpc://storage.googleapis.com",
    "dns:///storage.googleapis.com",
    "dns://8.8.8.8/storage.googleapis.com",
    "file:///etc/passwd",
    "ftp://storage.googleapis.com",
    "://storage.googleapis.com",
  ]) func badDefaultEndpoint(input: String) throws {
    let credentials = try Credentials(configuration: .anonymous)
    let options = ClientOptions().with {
      $0.credentials = credentials
    }
    let error = #expect(throws: ClientError.self) {
      let client = try _GRPCClient(from: options, withDefaultEndpoint: input)
      client.close()
    }
    guard case let .invalidEndpoint(msg) = error else {
      Issue.record(
        "Mismatched error type, want .invalidEndpoint, got=\(String(describing: error)).")
      return
    }
    #expect(msg == input, "error=\(String(describing: error))")
  }
}
