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
@_spi(GoogleCloudInternal) import GoogleGax
import struct NIOCore.TimeAmount
import NIOSSL
import Synchronization

enum ShowcaseServerError: Error, CustomStringConvertible, CustomDebugStringConvertible {
  case binaryNotFound
  case startupTimeout(String)

  var description: String {
    switch self {
    case .binaryNotFound:
      return "gapic-showcase binary not found at GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"
    case .startupTimeout(let detail):
      return "Timed out waiting for gapic-showcase startup: \(detail)"
    }
  }

  var debugDescription: String {
    switch self {
    case .binaryNotFound:
      return "ShowcaseServerError.binaryNotFound: \(self.description)"
    case .startupTimeout:
      return "ShowcaseServerError.startupTimeout: \(self.description)"
    }
  }
}

/// Adapts `AsyncHTTPClient.HTTPClient` to `GoogleGax._HTTPClientProtocol` for Showcase tests,
/// recording the TLS negotiation headers returned by Showcase (`x-showcase-tls-group` and
/// `x-showcase-tls-client-supported-groups`).
final class ShowcaseHTTPClient: _HTTPClientProtocol, Sendable {
  struct RecordedTLSHeaders: Sendable {
    var group: String?
    var clientSupportedGroups: String?
  }

  private let inner: AsyncHTTPClient.HTTPClient
  private let recorded = Mutex(RecordedTLSHeaders())

  init(configuration: AsyncHTTPClient.HTTPClient.Configuration) {
    self.inner = AsyncHTTPClient.HTTPClient(configuration: configuration)
  }

  var lastTLSGroup: String? {
    self.recorded.withLock { $0.group }
  }

  var lastClientSupportedGroups: String? {
    self.recorded.withLock { $0.clientSupportedGroups }
  }

  func shutdown() async throws {
    try await self.inner.shutdown()
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

final class ShowcaseServer: Sendable {
  let endpoint: String
  let caCertPEM: String
  private let process: Process
  private let tempDir: URL
  private let logHandle: FileHandle

  private init(
    endpoint: String,
    caCertPEM: String,
    process: Process,
    tempDir: URL,
    logHandle: FileHandle
  ) {
    self.endpoint = endpoint
    self.caCertPEM = caCertPEM
    self.process = process
    self.tempDir = tempDir
    self.logHandle = logHandle
  }

  private func stop() {
    if self.process.isRunning {
      self.process.terminate()
      self.process.waitUntilExit()
    }
    try? self.logHandle.close()
    try? FileManager.default.removeItem(at: self.tempDir)
  }

  func withHTTPClient(
    curves: [NIOTLSCurve]? = nil,
    _ body: (ShowcaseHTTPClient) async throws -> Void
  ) async throws {
    let certs = try NIOSSLCertificate.fromPEMBytes(Array(self.caCertPEM.utf8))
    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.trustRoots = .certificates(certs)
    if let curves {
      tlsConfiguration.curves = curves
    }
    var config = HTTPClient.Configuration(tlsConfiguration: tlsConfiguration)
    // `gapic-showcase` multiplexes gRPC (HTTP/2) and REST (HTTP/1.1) on the same port via cmux.
    config.httpVersion = .http1Only
    let httpClient = ShowcaseHTTPClient(configuration: config)
    do {
      try await body(httpClient)
    } catch {
      try? await httpClient.shutdown()
      throw error
    }
    try await httpClient.shutdown()
  }

  static func withServer(
    tlsGroups: String? = "0x11ec",
    _ body: (ShowcaseServer) async throws -> Void
  ) async throws {
    let server = try await Self.start(tlsGroups: tlsGroups)
    do {
      try await body(server)
    } catch {
      server.stop()
      throw error
    }
    server.stop()
  }

  private static func start(tlsGroups: String?) async throws -> ShowcaseServer {
    let binary = try findBinary()
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "showcase_\(ProcessInfo.processInfo.processIdentifier)_\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: tempDir,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let tempCAFile = tempDir.appendingPathComponent("ca.pem")
    let logFile = tempDir.appendingPathComponent("showcase.log")
    _ = FileManager.default.createFile(
      atPath: logFile.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    let logHandle = try FileHandle(forWritingTo: logFile)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    var args = [
      "run",
      "--port", ":0",
      "--fallback-port", ":0",
      "--tls",
      "--ca-cert-output-file", tempCAFile.path,
    ]
    if let tlsGroups {
      args.append(contentsOf: ["--tls-groups", tlsGroups])
    }
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["NO_PROXY"] = "localhost,127.0.0.1"
    env["no_proxy"] = "localhost,127.0.0.1"
    env.removeValue(forKey: "HTTP_PROXY")
    env.removeValue(forKey: "HTTPS_PROXY")
    env.removeValue(forKey: "http_proxy")
    env.removeValue(forKey: "https_proxy")
    process.environment = env
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = logHandle
    process.standardError = logHandle

    do {
      try process.run()
    } catch {
      try? logHandle.close()
      try? FileManager.default.removeItem(at: tempDir)
      throw error
    }

    let startupDeadline = Date().addingTimeInterval(30)
    var resolvedEndpoint: String?
    var resolvedCACert: String?
    var restListening = false

    while Date() < startupDeadline {
      if !process.isRunning {
        let logOutput = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        try? logHandle.close()
        try? FileManager.default.removeItem(at: tempDir)
        throw ShowcaseServerError.startupTimeout("Showcase exited early: \(logOutput)")
      }
      if resolvedCACert == nil,
        let content = try? String(contentsOf: tempCAFile, encoding: .utf8),
        content.contains("-----BEGIN CERTIFICATE-----")
      {
        resolvedCACert = content
      }
      if let logOutput = try? String(contentsOf: logFile, encoding: .utf8) {
        if resolvedEndpoint == nil,
          let match = logOutput.firstMatch(
            of: /HTTP\/REST Endpoint \(TLS\): (https:\/\/localhost:\d+)/)
        {
          resolvedEndpoint = String(match.1)
        }
        if !restListening && logOutput.contains("Listening for REST connections") {
          restListening = true
        }
      }
      if resolvedCACert != nil && resolvedEndpoint != nil && restListening {
        break
      }
      try await Task.sleep(for: .milliseconds(50))
    }

    guard let endpoint = resolvedEndpoint, let caCert = resolvedCACert, restListening else {
      let logOutput = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
      try? logHandle.close()
      try? FileManager.default.removeItem(at: tempDir)
      throw ShowcaseServerError.startupTimeout(logOutput)
    }

    return ShowcaseServer(
      endpoint: endpoint,
      caCertPEM: caCert,
      process: process,
      tempDir: tempDir,
      logHandle: logHandle
    )
  }

  private static func findBinary() throws -> String {
    guard let path = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_SHOWCASE_PATH"],
      FileManager.default.isExecutableFile(atPath: path)
    else {
      throw ShowcaseServerError.binaryNotFound
    }
    return path
  }
}
