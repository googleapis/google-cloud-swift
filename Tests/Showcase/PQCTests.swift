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

import AsyncHTTPClient
import Foundation
import GoogleAuth
import GoogleGax
import GoogleShowcaseV1Beta1
import NIOCore
import NIOSSL
import Testing

@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"] != nil,
    "Showcase tests require GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"
  )
) struct PQCTests {
  @Test func pqcUnaryRPC() async throws {
    let server = try await ShowcaseServer.start(tlsGroups: "0x11ec")
    defer { server.stop() }

    let options = try ClientOptions().with {
      $0.endpoint = server.endpoint
      $0.rootCertificates = server.caCertPEM
      $0.credentials = try Credentials(configuration: .anonymous)
      $0.retryPolicy = NeverRetry()
    }
    let client = try EchoClient(options)

    let testContent = "testing PQC transport compliance (HTTP unary)"
    let response = try await client.echo(
      request: .init().with { $0.response = .content(testContent) }
    )

    #expect(response.content == testContent)
  }

  @Test func pqcRejectedWhenPQCDisabled() async throws {
    let server = try await ShowcaseServer.start(
      port: 7473,
      fallbackPort: 1341,
      tlsGroups: "0x11ec"
    )
    defer { server.stop() }

    // Configure a client with classical curves only (excluding x25519_MLKEM768).
    let certs = try NIOSSLCertificate.fromPEMBytes(Array(server.caCertPEM.utf8))
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.trustRoots = .certificates(certs)
    tlsConfiguration.curves = [.x25519, .secp256r1]

    let httpClient = AsyncHTTPClient.HTTPClient(
      configuration: .init(tlsConfiguration: tlsConfiguration)
    )
    defer {
      let client = httpClient
      Task {
        try? await client.shutdown()
      }
    }

    var request = HTTPClientRequest(url: "\(server.endpoint)/v1beta1/echo:echo")
    request.method = .POST
    request.headers.add(name: "Content-Type", value: "application/json")
    request.body = .bytes(ByteBuffer(string: "{\"content\":\"test\"}"))

    // The server is pinned to 0x11ec (X25519MLKEM768), so a client offering only classical curves
    // must fail the TLS handshake.
    await #expect(throws: (any Error).self) {
      _ = try await httpClient.execute(request, timeout: .seconds(5))
    }
  }
}
