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
@_spi(GoogleCloudInternal) @testable import GoogleGax
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix
import Synchronization
import Testing

@Suite struct HTTPClientHolderTests {
  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func getDoesNotFollowRedirects(statusCode: UInt) async throws {
    try await withLoopbackRedirectServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirect-body".utf8)
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let credentials = try Credentials(configuration: .apiKey("test-api-key"))
      let endpoint = "http://127.0.0.1:\(sourcePort)"
      let options = ClientOptions().with {
        $0.endpoint = endpoint
        $0.credentials = credentials
        $0.quotaProject = "test-quota-project"
      }
      let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
      #expect(client.inner is HTTPClientHolder)

      let reqOptions = RequestOptions().with {
        $0.headers = [
          ("x-goog-encryption-key", "test-csek-key"),
          ("x-custom-header", "custom-value"),
        ]
      }
      var request = try await client.newRequest(
        path: "/v1/resource", query: [], options: reqOptions)
      request.setMethod(.GET)
      let response = try await request.execute()
      let body = try await response.data()

      #expect(response.status.code == statusCode)
      #expect(
        response.headers.first(name: "Location") == "http://127.0.0.1:\(targetPort)/redirect-target"
      )
      #expect(body == Data("redirect-body".utf8))

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .GET)
      #expect(sourceRequests.first?.uri == "/v1/resource")
      #expect(sourceRequests.first?.headers["x-goog-api-key"] == ["test-api-key"])
      #expect(sourceRequests.first?.headers["x-goog-user-project"] == ["test-quota-project"])
      #expect(sourceRequests.first?.headers["x-goog-encryption-key"] == ["test-csek-key"])
      #expect(sourceRequests.first?.headers["x-custom-header"] == ["custom-value"])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func postDoesNotFollowRedirects(statusCode: UInt) async throws {
    try await withLoopbackRedirectServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirect-body".utf8)
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let credentials = try Credentials(configuration: .apiKey("test-api-key"))
      let endpoint = "http://127.0.0.1:\(sourcePort)"
      let options = ClientOptions().with {
        $0.endpoint = endpoint
        $0.credentials = credentials
        $0.quotaProject = "test-quota-project"
      }
      let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
      #expect(client.inner is HTTPClientHolder)

      let reqOptions = RequestOptions().with {
        $0.headers = [
          ("x-goog-encryption-key", "test-csek-key"),
          ("x-custom-header", "custom-value"),
        ]
      }
      var request = try await client.newRequest(path: "/v1/upload", query: [], options: reqOptions)
      request.setMethod(.POST)
      let payload = Data("test-post-payload".utf8)
      request.setBody(data: payload, ofContentType: "application/octet-stream")
      let response = try await request.execute()
      let body = try await response.data()

      #expect(response.status.code == statusCode)
      #expect(
        response.headers.first(name: "Location") == "http://127.0.0.1:\(targetPort)/redirect-target"
      )
      #expect(body == Data("redirect-body".utf8))

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .POST)
      #expect(sourceRequests.first?.uri == "/v1/upload")
      #expect(sourceRequests.first?.body == payload)
      #expect(sourceRequests.first?.headers["x-goog-api-key"] == ["test-api-key"])
      #expect(sourceRequests.first?.headers["x-goog-user-project"] == ["test-quota-project"])
      #expect(sourceRequests.first?.headers["x-goog-encryption-key"] == ["test-csek-key"])
      #expect(sourceRequests.first?.headers["x-custom-header"] == ["custom-value"])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test func gcs308ResumeIncompleteWithLocationReturns308Cleanly() async throws {
    let recorder = LoopbackRequestRecorder()
    try await withLoopbackServer(handlerFactory: { port in
      let sessionURL =
        "http://127.0.0.1:\(port)/upload/storage/v1/b/test-bucket/o?uploadType=resumable&upload_id=session-123"
      return LoopbackStaticServerHandler(
        status: .permanentRedirect,
        headers: NIOHTTP1.HTTPHeaders([
          ("Location", sessionURL),
          ("Range", "bytes=0-42"),
        ]),
        body: Data(),
        recorder: recorder
      )
    }) { port in
      let endpoint = "http://127.0.0.1:\(port)"
      let sessionURL =
        "\(endpoint)/upload/storage/v1/b/test-bucket/o?uploadType=resumable&upload_id=session-123"
      let credentials = try Credentials(configuration: .anonymous)
      let options = ClientOptions().with {
        $0.endpoint = endpoint
        $0.credentials = credentials
      }
      let client = try _HTTPClient(from: options, withDefaultEndpoint: endpoint)
      #expect(client.inner is HTTPClientHolder)

      var request = try await client.newRequest(uri: sessionURL)
      request.setMethod(.PUT)
      request.setHeader(name: "Content-Range", value: "bytes */100")

      let response = try await request.execute()
      await response.drain()

      #expect(response.status.code == 308)
      #expect(response.headers.first(name: "Range") == "bytes=0-42")
      #expect(response.headers.first(name: "Location") == sessionURL)
      #expect(recorder.requests.count == 1)
    }
  }
}

private struct RecordedLoopbackRequest: Sendable {
  let method: HTTPMethod
  let uri: String
  let headers: NIOHTTP1.HTTPHeaders
  let body: Data
}

private final class LoopbackRequestRecorder: Sendable {
  private let recorded = Mutex<[RecordedLoopbackRequest]>([])

  func record(_ request: RecordedLoopbackRequest) {
    self.recorded.withLock { $0.append(request) }
  }

  var requests: [RecordedLoopbackRequest] {
    self.recorded.withLock { $0 }
  }
}

private func withLoopbackServer<T>(
  handlerFactory: @escaping @Sendable (_ port: Int) -> LoopbackStaticServerHandler,
  _ operation: (_ port: Int) async throws -> T
) async throws -> T {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  let portHolder = Mutex<Int?>(nil)
  var serverChannel: (any Channel)? = nil
  let result: Result<T, any Error>
  do {
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          let port = portHolder.withLock { $0 } ?? 0
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(handlerFactory(port))
        }
      }
    let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    serverChannel = channel
    let port = try #require(channel.localAddress?.port)
    portHolder.withLock { $0 = port }
    result = .success(try await operation(port))
  } catch {
    result = .failure(error)
  }

  try? await serverChannel?.close().get()
  switch result {
  case .success(let value):
    try await group.shutdownGracefully()
    return value
  case .failure(let error):
    try? await group.shutdownGracefully()
    throw error
  }
}

private func withLoopbackRedirectServers<T>(
  status: HTTPResponseStatus,
  responseBody: Data,
  contentType: String = "text/plain; charset=utf-8",
  _ operation: (
    _ sourcePort: Int,
    _ targetPort: Int,
    _ sourceRecorder: LoopbackRequestRecorder,
    _ targetRecorder: LoopbackRequestRecorder
  ) async throws -> T
) async throws -> T {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  let sourceRecorder = LoopbackRequestRecorder()
  let targetRecorder = LoopbackRequestRecorder()

  var sourceChannel: (any Channel)? = nil
  var targetChannel: (any Channel)? = nil
  let result: Result<T, any Error>
  do {
    let targetBootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(
            LoopbackStaticServerHandler(
              status: .ok,
              headers: NIOHTTP1.HTTPHeaders([("Content-Type", "application/json")]),
              body: Data(#"{"status": "unexpected"}"#.utf8),
              recorder: targetRecorder
            )
          )
        }
      }
    let boundTarget = try await targetBootstrap.bind(host: "127.0.0.1", port: 0).get()
    targetChannel = boundTarget
    let targetPort = try #require(boundTarget.localAddress?.port)

    let sourceHeaders = NIOHTTP1.HTTPHeaders([
      ("Location", "http://127.0.0.1:\(targetPort)/redirect-target"),
      ("Content-Type", contentType),
    ])
    let sourceBootstrap = ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 4)
      .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.configureHTTPServerPipeline()
          try channel.pipeline.syncOperations.addHandler(
            NIOHTTPServerRequestAggregator(maxContentLength: 1 << 16))
          try channel.pipeline.syncOperations.addHandler(
            LoopbackStaticServerHandler(
              status: status,
              headers: sourceHeaders,
              body: responseBody,
              recorder: sourceRecorder
            )
          )
        }
      }
    let boundSource = try await sourceBootstrap.bind(host: "127.0.0.1", port: 0).get()
    sourceChannel = boundSource
    let sourcePort = try #require(boundSource.localAddress?.port)

    result = .success(try await operation(sourcePort, targetPort, sourceRecorder, targetRecorder))
  } catch {
    result = .failure(error)
  }

  try? await sourceChannel?.close().get()
  try? await targetChannel?.close().get()
  switch result {
  case .success(let value):
    try await group.shutdownGracefully()
    return value
  case .failure(let error):
    try? await group.shutdownGracefully()
    throw error
  }
}

private final class LoopbackStaticServerHandler: ChannelInboundHandler {
  typealias InboundIn = NIOHTTPServerRequestFull
  typealias OutboundOut = HTTPServerResponsePart

  private let status: HTTPResponseStatus
  private let headers: NIOHTTP1.HTTPHeaders
  private let body: Data
  private let recorder: LoopbackRequestRecorder

  init(
    status: HTTPResponseStatus,
    headers: NIOHTTP1.HTTPHeaders,
    body: Data,
    recorder: LoopbackRequestRecorder
  ) {
    self.status = status
    self.headers = headers
    self.body = body
    self.recorder = recorder
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let request = self.unwrapInboundIn(data)
    self.recorder.record(
      RecordedLoopbackRequest(
        method: request.head.method,
        uri: request.head.uri,
        headers: request.head.headers,
        body: request.body.map { Data(buffer: $0) } ?? Data()
      )
    )
    var responseHeaders = self.headers
    responseHeaders.replaceOrAdd(name: "Content-Length", value: "\(self.body.count)")
    responseHeaders.replaceOrAdd(name: "Connection", value: "close")
    let head = HTTPResponseHead(
      version: request.head.version,
      status: self.status,
      headers: responseHeaders
    )
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    if !self.body.isEmpty {
      let buffer = context.channel.allocator.buffer(data: self.body)
      context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    }
    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
  }
}
