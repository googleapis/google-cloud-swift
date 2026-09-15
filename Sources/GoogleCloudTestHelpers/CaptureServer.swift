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
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

/// A minimal HTTP/1.1 server that records the requests it receives.
///
/// The generated clients create their own HTTP client, we cannot mock the transport. Tests point
/// a client at this server using `ClientOptions.endpoint` and then inspect the captured request.
/// The server always replies with the same canned payload.
public final class CaptureServer: Sendable {
  /// A request received by the server.
  public struct CapturedRequest: Sendable {
    public let method: HTTPMethod
    public let uri: String
    public let body: Data

    /// The request body parsed as a JSON object.
    public func json() throws -> [String: Any] {
      let parsed = try JSONSerialization.jsonObject(with: self.body)
      guard let object = parsed as? [String: Any] else {
        throw CaptureServerError.invalidBody
      }
      return object
    }
  }

  private let group: MultiThreadedEventLoopGroup
  private let channel: any Channel
  private let recorded: NIOLockedValueBox<[CapturedRequest]>

  /// The port where the server is listening.
  public var port: Int { self.channel.localAddress?.port ?? 0 }

  /// The endpoint to use in `ClientOptions`.
  public var endpoint: String { "http://127.0.0.1:\(self.port)" }

  /// The requests received so far.
  public var requests: [CapturedRequest] { self.recorded.withLockedValue { $0 } }

  /// Starts a server replying with `response` to every request.
  public init(responding response: Data = Data("{}".utf8)) async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let recorded = NIOLockedValueBox<[CapturedRequest]>([])
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 16)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 20))
          try channel.pipeline.syncOperations.addHandler(
            CaptureHandler(recorded: recorded, response: response))
        }
      }
    do {
      self.channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    } catch {
      try? await group.shutdownGracefully()
      throw error
    }
    self.group = group
    self.recorded = recorded
  }

  /// Stops the server, releasing all its resources.
  public func shutdown() async throws {
    try? await self.channel.close().get()
    try await self.group.shutdownGracefully()
  }

  /// Runs `body` against a running server, stopping the server on the way out.
  public static func withServer(
    responding response: Data = Data("{}".utf8),
    _ body: (CaptureServer) async throws -> Void
  ) async throws {
    let server = try await CaptureServer(responding: response)
    do {
      try await body(server)
    } catch {
      try? await server.shutdown()
      throw error
    }
    try await server.shutdown()
  }
}

/// The errors reported by ``CaptureServer``.
public enum CaptureServerError: Swift.Error {
  /// The request body is not a JSON object.
  case invalidBody
}

/// Records each request and replies with a canned response.
private final class CaptureHandler: ChannelInboundHandler {
  typealias InboundIn = NIOHTTPServerRequestFull
  typealias OutboundOut = HTTPServerResponsePart

  private let recorded: NIOLockedValueBox<[CaptureServer.CapturedRequest]>
  private let response: Data

  init(recorded: NIOLockedValueBox<[CaptureServer.CapturedRequest]>, response: Data) {
    self.recorded = recorded
    self.response = response
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let request = self.unwrapInboundIn(data)
    let body = request.body.map { Data($0.readableBytesView) } ?? Data()
    self.recorded.withLockedValue {
      $0.append(
        .init(method: request.head.method, uri: request.head.uri, body: body))
    }

    var headers = HTTPHeaders()
    headers.add(name: "Content-Type", value: "application/json")
    headers.add(name: "Content-Length", value: "\(self.response.count)")
    let head = HTTPResponseHead(version: request.head.version, status: .ok, headers: headers)
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    var buffer = context.channel.allocator.buffer(capacity: self.response.count)
    buffer.writeBytes(self.response)
    context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
  }
}
