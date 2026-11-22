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
import GRPCCore
import GRPCNIOTransportCore
import GRPCNIOTransportHTTP2Posix
import PubSubConformanceProxyCore
import Synchronization

@main
struct PubSubConformanceProxyMain {
  static func main() async throws {
    let port = Self.parsePort(arguments: Array(CommandLine.arguments.dropFirst()))
    try await Self.runProxyServer(port: port)
  }

  @concurrent
  private static func runProxyServer(port: Int) async throws {
    final class ServerBox: Sendable {
      let value = Mutex<GRPCServer<HTTP2ServerTransport.Posix>?>(nil)
    }
    let serverBox = ServerBox()
    let service = PubSubProxyService {
      serverBox.value.withLock { $0 }?.beginGracefulShutdown()
    }

    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: port),
      transportSecurity: .plaintext,
      config: .defaults {
        $0.rpc.maxRequestPayloadSize = 64 * 1024 * 1024
        $0.http2.maxHeaderListSize = 4 * 1024 * 1024
        $0.http2.maxConcurrentStreams = 1_024
        $0.http2.rateLimits.controlFrames = RateLimit(maxCount: 65_535, window: .seconds(10))
      }
    )

    let server = GRPCServer(transport: transport, services: [service])
    serverBox.value.withLock { $0 = server }

    let serveTask = Task {
      try await server.serve()
    }

    let listening = try await transport.listeningAddress
    guard let ipv4 = listening.ipv4 else {
      serveTask.cancel()
      server.beginGracefulShutdown()
      throw CancellationError()
    }

    FileHandle.standardOutput.write(Data("READY 127.0.0.1:\(ipv4.port)\n".utf8))
    try await serveTask.value
  }

  private static func parsePort(arguments: [String]) -> Int {
    var idx = 0
    while idx < arguments.count {
      let arg = arguments[idx]
      if arg.hasPrefix("--port="), let val = Int(arg.dropFirst("--port=".count)) {
        return val
      }
      if arg == "--port", idx + 1 < arguments.count, let val = Int(arguments[idx + 1]) {
        return val
      }
      idx += 1
    }
    return 0
  }
}
