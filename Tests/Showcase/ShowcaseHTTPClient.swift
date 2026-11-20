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
@_spi(GoogleCloudInternal) import GoogleGax
import struct NIOCore.TimeAmount
import NIOSSL
import Synchronization

/// An HTTP transport adapter conforming to `GoogleGax._HTTPClientProtocol` for testing generated
/// REST clients against a local Auto-TLS `gapic-showcase` server.
///
/// Generated GAPIC clients (such as `EchoClient`) normally construct an internal
/// `GoogleGax.HTTPClientHolder` that uses system TLS trust roots and negotiates HTTP/2 via ALPN.
/// Connecting to `gapic-showcase --tls` requires a custom transport injected via
/// `ClientOptions._httpClient` for three reasons:
/// 1. **Ephemeral CA trust:** Trusts the self-signed CA certificate generated at startup by
///    `gapic-showcase --tls`.
/// 2. **HTTP/1.1 routing (`cmux`):** `gapic-showcase` multiplexes gRPC and REST on a single port
///    using `cmux`, routing all HTTP/2 connections to its gRPC server and only HTTP/1.1
///    connections to its REST handlers. Setting `.http1Only` ensures REST RPCs reach the REST
///    server instead of failing with `HTTP/2 415`.
/// 3. **TLS header inspection & curve overrides:** Records Showcase's echoed TLS metadata headers
///    (`x-showcase-tls-group` and `x-showcase-tls-client-supported-groups`) so tests can verify
///    the negotiated key-exchange group while calling high-level client methods, and optionally
///    restricts client-offered TLS curves (`NIOTLSCurve`) for negative handshake tests.
final class ShowcaseHTTPClient: _HTTPClientProtocol, Sendable {
  private struct RecordedTLSHeaders: Sendable {
    var group: String?
    var clientSupportedGroups: String?
  }

  private let inner: AsyncHTTPClient.HTTPClient
  private let recorded = Mutex(RecordedTLSHeaders())

  /// Creates a client trusting `caCertPEM` over HTTP/1.1, optionally restricting offered TLS
  /// key-exchange `curves` (leaving `curves` `nil` preserves `NIOSSL`'s default curve list).
  init(caCertPEM: String, curves: [NIOTLSCurve]? = nil) throws {
    let certs = try NIOSSLCertificate.fromPEMBytes(Array(caCertPEM.utf8))
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.trustRoots = .certificates(certs)
    if let curves {
      tlsConfiguration.curves = curves
    }
    var config = HTTPClient.Configuration(tlsConfiguration: tlsConfiguration)
    config.httpVersion = .http1Only
    self.inner = AsyncHTTPClient.HTTPClient(configuration: config)
  }

  deinit {
    let copy = self.inner
    Task {
      try? await copy.shutdown()
    }
  }

  /// The `x-showcase-tls-group` header from the most recent HTTP response, naming the TLS
  /// key-exchange group negotiated for the connection (e.g., `"X25519MLKEM768"`).
  var lastTLSGroup: String? {
    self.recorded.withLock { $0.group }
  }

  /// The `x-showcase-tls-client-supported-groups` header from the most recent HTTP response,
  /// listing the comma-separated key-exchange groups advertised in the client's `ClientHello`.
  var lastClientSupportedGroups: String? {
    self.recorded.withLock { $0.clientSupportedGroups }
  }

  @concurrent
  func execute(request: HTTPClientRequest, timeout: Duration) async throws -> HTTPClientResponse {
    let response = try await self.inner.execute(request, timeout: .init(timeout), logger: nil)
    let group = response.headers.first(name: "x-showcase-tls-group")
    let supportedGroups = response.headers.first(name: "x-showcase-tls-client-supported-groups")
    self.recorded.withLock {
      $0.group = group
      $0.clientSupportedGroups = supportedGroups
    }
    return response
  }
}
