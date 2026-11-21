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
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleCloudStorage
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix
import Synchronization
import Testing

@Suite struct StorageHTTPClientHolderTests {
  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func readObjectDoesNotFollowRedirects(statusCode: UInt) async throws {
    try await withLoopbackRedirectServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirected".utf8)
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
      let options = try StorageClientOptions().with {
        $0.client = try .init().with {
          $0.endpoint = "http://127.0.0.1:\(sourcePort)"
          $0.credentials = try Credentials(configuration: .apiKey("test-storage-api-key"))
          $0.quotaProject = "test-quota-project"
          $0.retryPolicy = NeverRetry()
        }
        $0.connectionPoolSize = 1
      }
      let client = try StorageClient(options)
      let readOptions = ReadObjectOptions().with {
        $0.customerEncryptionKey = csek
        $0.resumePolicy = NeverResume()
      }

      let handle = client.readObject(from: "test-bucket", object: "test-obj", options: readOptions)
      let error = await #expect(throws: ReadObjectError.self) {
        _ = try await handle.metadata
      }

      guard case .requestError(.http(let details)) = error else {
        Issue.record(
          "Expected ReadObjectError.requestError(.http), got \(String(describing: error))"
        )
        return
      }
      #expect(details.statusCode == Int(statusCode))
      #expect(
        details.headers["Location"] == "http://127.0.0.1:\(targetPort)/redirect-target"
      )

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.headers["x-goog-api-key"] == ["test-storage-api-key"])
      #expect(sourceRequests.first?.headers["x-goog-user-project"] == ["test-quota-project"])
      #expect(sourceRequests.first?.headers["x-goog-encryption-key"] == [csek.keyBase64])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func writeObjectDoesNotFollowRedirects(statusCode: UInt) async throws {
    try await withLoopbackRedirectServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirected".utf8)
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
      let options = try StorageClientOptions().with {
        $0.client = try .init().with {
          $0.endpoint = "http://127.0.0.1:\(sourcePort)"
          $0.credentials = try Credentials(configuration: .apiKey("test-storage-api-key"))
          $0.quotaProject = "test-quota-project"
          $0.retryPolicy = NeverRetry()
        }
        $0.connectionPoolSize = 1
      }
      let client = try StorageClient(options)
      let writeOptions = WriteObjectOptions().with {
        $0.customerEncryptionKey = csek
        $0.idempotent = true
        $0.resumePolicy = NeverResume()
      }

      let error = await #expect(throws: WriteObjectError.self) {
        _ = try await client.writeObject(
          Data("test-upload-payload".utf8),
          to: "test-bucket",
          as: "test-obj",
          options: writeOptions
        )
      }

      guard case .requestError(.http(let details)) = error else {
        Issue.record(
          "Expected WriteObjectError.requestError(.http), got \(String(describing: error))"
        )
        return
      }
      #expect(details.statusCode == Int(statusCode))
      #expect(
        details.headers["Location"] == "http://127.0.0.1:\(targetPort)/redirect-target"
      )

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .POST)
      #expect(sourceRequests.first?.headers["x-goog-api-key"] == ["test-storage-api-key"])
      #expect(sourceRequests.first?.headers["x-goog-user-project"] == ["test-quota-project"])
      #expect(sourceRequests.first?.headers["x-goog-encryption-key"] == [csek.keyBase64])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test(arguments: [UInt(301), 302, 303, 307, 308])
  func resumableUploadStartDoesNotFollowRedirects(statusCode: UInt) async throws {
    try await withLoopbackRedirectServers(
      status: HTTPResponseStatus(statusCode: Int(statusCode)),
      responseBody: Data("redirected".utf8)
    ) { sourcePort, targetPort, sourceRecorder, targetRecorder in
      let csek = try CustomerEncryptionKeyOptions(key: Data(repeating: 0x42, count: 32))
      let options = try StorageClientOptions().with {
        $0.client = try .init().with {
          $0.endpoint = "http://127.0.0.1:\(sourcePort)"
          $0.credentials = try Credentials(configuration: .apiKey("test-storage-api-key"))
          $0.quotaProject = "test-quota-project"
          $0.retryPolicy = NeverRetry()
        }
        $0.connectionPoolSize = 1
      }
      let client = try StorageClient(options)
      let writeOptions = WriteObjectOptions().with {
        $0.customerEncryptionKey = csek
        $0.resumableUploadThreshold = 0
        $0.resumePolicy = NeverResume()
      }

      let error = await #expect(throws: WriteObjectError.self) {
        _ = try await client.writeObject(
          Data("test-upload-payload".utf8),
          to: "test-bucket",
          as: "test-obj",
          options: writeOptions
        )
      }

      guard case .requestError(.http(let details)) = error else {
        Issue.record(
          "Expected WriteObjectError.requestError(.http), got \(String(describing: error))"
        )
        return
      }
      #expect(details.statusCode == Int(statusCode))
      #expect(
        details.headers["Location"] == "http://127.0.0.1:\(targetPort)/redirect-target"
      )

      let sourceRequests = sourceRecorder.requests
      #expect(sourceRequests.count == 1)
      #expect(sourceRequests.first?.method == .POST)
      #expect(sourceRequests.first?.headers["x-goog-api-key"] == ["test-storage-api-key"])
      #expect(sourceRequests.first?.headers["x-goog-user-project"] == ["test-quota-project"])
      #expect(sourceRequests.first?.headers["x-goog-encryption-key"] == [csek.keyBase64])
      #expect(targetRecorder.requests.isEmpty)
    }
  }

  @Test func chunkedResumableUploadHandles308ResumeIncompleteWithLocationHeader() async throws {
    let payload = Data(repeating: 0x41, count: 64)
    let recorder = LoopbackRequestRecorder()

    try await withLoopbackResumableUploadServer(
      recorder: recorder,
      objectName: "test-obj",
      bucketName: "test-bucket",
      totalSize: payload.count
    ) { port in
      let endpoint = "http://127.0.0.1:\(port)"
      let options = try StorageClientOptions().with {
        $0.client = try .init().with {
          $0.endpoint = endpoint
          $0.credentials = try Credentials(configuration: .anonymous)
        }
        $0.connectionPoolSize = 1
      }
      let client = try StorageClient(options)
      let writeOptions = WriteObjectOptions().with {
        $0.resumableUploadThreshold = 0
        $0.chunkSize = 32
        $0.checksums = .none
      }

      let object = try await client.writeObject(
        payload,
        to: "test-bucket",
        as: "test-obj",
        options: writeOptions
      )

      #expect(object.name == "test-obj")
      #expect(object.bucket == "projects/_/buckets/test-bucket")
      #expect(object.size == 64)

      let requests = recorder.requests
      #expect(requests.count == 3)
      #expect(requests[0].method == .POST)
      #expect(requests[1].method == .PUT)
      #expect(requests[1].headers["Content-Range"] == ["bytes 0-31/64"])
      #expect(requests[1].body == payload.subdata(in: 0..<32))
      #expect(requests[2].method == .PUT)
      #expect(requests[2].headers["Content-Range"] == ["bytes 32-63/64"])
      #expect(requests[2].body == payload.subdata(in: 32..<64))
    }
  }

  @Test func resumableUploadHandles308ResumeIncompleteWithSameLocationHeader() async throws {
    let payload = Data(repeating: 0x41, count: 64)
    let recorder = LoopbackRequestRecorder()

    try await withLoopbackResumableUploadServer(
      recorder: recorder,
      objectName: "test-obj",
      bucketName: "test-bucket",
      totalSize: payload.count
    ) { port in
      let endpoint = "http://127.0.0.1:\(port)"
      let sessionURL =
        "\(endpoint)/upload/storage/v1/b/test-bucket/o?uploadType=resumable&upload_id=session-123"
      let options = try StorageClientOptions().with {
        $0.client = try .init().with {
          $0.endpoint = endpoint
          $0.credentials = try Credentials(configuration: .anonymous)
        }
        $0.connectionPoolSize = 1
      }
      let client = try StorageClient(options)
      let writeOptions = WriteObjectOptions().with {
        $0.checksums = .none
      }

      let object = try await client.resumeWriteObject(
        BytesSource(data: payload),
        uploadId: sessionURL,
        options: writeOptions
      )

      #expect(object.name == "test-obj")
      #expect(object.bucket == "projects/_/buckets/test-bucket")
      #expect(object.size == 64)

      let requests = recorder.requests
      #expect(requests.count == 2)
      #expect(requests[0].method == .PUT)
      #expect(requests[0].headers["Content-Range"] == ["bytes */*"])
      #expect(requests[1].method == .PUT)
      #expect(requests[1].headers["Content-Range"] == ["bytes 43-63/64"])
      #expect(requests[1].body == payload.subdata(in: 43..<64))
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

private func withLoopbackResumableUploadServer<T>(
  recorder: LoopbackRequestRecorder,
  objectName: String,
  bucketName: String,
  totalSize: Int,
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
          try channel.pipeline.syncOperations.addHandler(
            LoopbackResumableUploadHandler(
              port: port,
              objectName: objectName,
              bucketName: bucketName,
              totalSize: totalSize,
              recorder: recorder
            )
          )
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
      ("Content-Type", "text/plain; charset=utf-8"),
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

private final class LoopbackResumableUploadHandler: ChannelInboundHandler {
  typealias InboundIn = NIOHTTPServerRequestFull
  typealias OutboundOut = HTTPServerResponsePart

  private let port: Int
  private let objectName: String
  private let bucketName: String
  private let totalSize: Int
  private let recorder: LoopbackRequestRecorder

  init(
    port: Int,
    objectName: String,
    bucketName: String,
    totalSize: Int,
    recorder: LoopbackRequestRecorder
  ) {
    self.port = port
    self.objectName = objectName
    self.bucketName = bucketName
    self.totalSize = totalSize
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

    let sessionURL =
      "http://127.0.0.1:\(self.port)/upload/storage/v1/b/\(self.bucketName)/o?uploadType=resumable&upload_id=session-123"
    if request.head.method == .POST {
      let headers = NIOHTTP1.HTTPHeaders([
        ("Location", sessionURL),
        ("Content-Length", "0"),
        ("Connection", "close"),
      ])
      let head = HTTPResponseHead(
        version: request.head.version,
        status: .ok,
        headers: headers
      )
      context.write(self.wrapOutboundOut(.head(head)), promise: nil)
      context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      return
    }

    let contentRange = request.head.headers.first(name: "Content-Range") ?? ""
    if contentRange.hasPrefix("bytes */") {
      let headers = NIOHTTP1.HTTPHeaders([
        ("Location", sessionURL),
        ("Range", "bytes=0-42"),
        ("Content-Length", "0"),
        ("Connection", "close"),
      ])
      let head = HTTPResponseHead(
        version: request.head.version,
        status: .permanentRedirect,
        headers: headers
      )
      context.write(self.wrapOutboundOut(.head(head)), promise: nil)
      context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      return
    }

    if contentRange == "bytes 0-31/\(self.totalSize)" {
      let headers = NIOHTTP1.HTTPHeaders([
        ("Location", sessionURL),
        ("Range", "bytes=0-31"),
        ("Content-Length", "0"),
        ("Connection", "close"),
      ])
      let head = HTTPResponseHead(
        version: request.head.version,
        status: .permanentRedirect,
        headers: headers
      )
      context.write(self.wrapOutboundOut(.head(head)), promise: nil)
      context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      return
    }

    let objectJSON = """
      {
        "name": "\(self.objectName)",
        "bucket": "\(self.bucketName)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(self.totalSize)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """
    let body = Data(objectJSON.utf8)
    let headers = NIOHTTP1.HTTPHeaders([
      ("Content-Type", "application/json"),
      ("Content-Length", "\(body.count)"),
      ("Connection", "close"),
    ])
    let head = HTTPResponseHead(
      version: request.head.version,
      status: .ok,
      headers: headers
    )
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    let buffer = context.channel.allocator.buffer(data: body)
    context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
  }
}
