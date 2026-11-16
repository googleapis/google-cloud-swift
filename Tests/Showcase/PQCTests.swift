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
import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
import GoogleShowcaseV1Beta1
import NIOSSL
import Testing

@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"] != nil,
    "Showcase tests require GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"
  )
) struct PQCTests {
  @Test func echoUnarySucceedsWithPQC() async throws {
    try await ShowcaseServer.withServer(tlsGroups: "0x11ec") { server in
      try await server.withHTTPClient { httpClient in
        let options = try ClientOptions().with {
          $0.endpoint = server.endpoint
          $0._httpClient = httpClient
          $0.credentials = try Credentials(configuration: .anonymous)
          $0.retryPolicy = NeverRetry()
        }
        let client = try EchoClient(options)

        let testContent = "testing PQC transport compliance (HTTP unary)"
        let response = try await client.echo(
          request: .init().with { $0.response = .content(testContent) }
        )

        #expect(response.content == testContent)
        #expect(httpClient.lastTLSGroup == "X25519MLKEM768")
        let supportedGroups = try #require(httpClient.lastClientSupportedGroups)
        #expect(supportedGroups.split(separator: ",").contains("X25519MLKEM768"))
      }
    }
  }

  @Test func echoUnaryFailsWhenClientDisablesPQC() async throws {
    try await ShowcaseServer.withServer(tlsGroups: "0x11ec") { server in
      // Restrict the client to classical curves only (excluding X25519MLKEM768 / 0x11ec).
      try await server.withHTTPClient(curves: [.x25519, .secp256r1]) { httpClient in
        let options = try ClientOptions().with {
          $0.endpoint = server.endpoint
          $0._httpClient = httpClient
          $0.credentials = try Credentials(configuration: .anonymous)
          $0.retryPolicy = NeverRetry()
        }
        let client = try EchoClient(options)

        let error = await #expect(throws: RequestError.self) {
          _ = try await client.echo(
            request: .init().with { $0.response = .content("should fail TLS handshake") }
          )
        }
        guard case .io(let underlying) = error else {
          Issue.record("Expected RequestError.io from TLS handshake failure, got \(error)")
          return
        }
        #expect(underlying is NIOSSLError)
      }
    }
  }
}
