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
package import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import GoogleWKT
import Synchronization
package import _GoogleCloudPubSubProtos
import SwiftProtobuf
@testable import GoogleCloudPubSub

package final class FakeStreamingPullSession: Sendable {
  package enum OutboundEvent: Sendable {
    case response(Google_Pubsub_V1_StreamingPullResponse)
    case close(RPCError?)
  }

  private struct State: Sendable {
    var receivedFrames: [Google_Pubsub_V1_StreamingPullRequest] = []
    var frameWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var closed = false
    var clientCanceled = false
  }

  package let id: Int
  package let metadata: [String: [String]]
  private let state = Mutex(State())
  private let continuation: AsyncStream<OutboundEvent>.Continuation
  fileprivate let outboundStream: AsyncStream<OutboundEvent>

  fileprivate init(id: Int, metadata: [String: [String]]) {
    self.id = id
    self.metadata = metadata
    let (stream, cont) = AsyncStream<OutboundEvent>.makeStream()
    self.outboundStream = stream
    self.continuation = cont
  }

  package var frames: [Google_Pubsub_V1_StreamingPullRequest] {
    self.state.withLock { $0.receivedFrames }
  }

  package var isClientCanceled: Bool {
    self.state.withLock { $0.clientCanceled }
  }

  fileprivate func appendFrame(_ frame: Google_Pubsub_V1_StreamingPullRequest) {
    let waitersToWake = self.state.withLock {
      state -> [CheckedContinuation<Void, Never>] in
      state.receivedFrames.append(frame)
      let count = state.receivedFrames.count
      var ready: [CheckedContinuation<Void, Never>] = []
      var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
      for waiter in state.frameWaiters {
        if count >= waiter.target {
          ready.append(waiter.continuation)
        } else {
          remaining.append(waiter)
        }
      }
      state.frameWaiters = remaining
      return ready
    }
    for waiter in waitersToWake {
      waiter.resume()
    }
  }

  fileprivate func markClientCanceled() {
    self.state.withLock { $0.clientCanceled = true }
  }

  package func waitForFrames(atLeast count: Int) async {
    await withCheckedContinuation { continuation in
      let alreadyMet = self.state.withLock { state -> Bool in
        if state.receivedFrames.count >= count {
          return true
        }
        state.frameWaiters.append((count, continuation))
        return false
      }
      if alreadyMet {
        continuation.resume()
      }
    }
  }

  package func sendResponse(_ response: Google_Pubsub_V1_StreamingPullResponse) {
    self.continuation.yield(.response(response))
  }

  package func close(error: RPCError? = nil) {
    let shouldClose = self.state.withLock { state -> Bool in
      if state.closed { return false }
      state.closed = true
      return true
    }
    if shouldClose {
      self.continuation.yield(.close(error))
      self.continuation.finish()
    }
  }
}

package final class FakePubSubServer: Sendable {
  package struct CapturedCall: Sendable {
    package let seq: Int
    package let method: String
    package let metadata: [String: [String]]
    package let publishRequest: Google_Pubsub_V1_PublishRequest?
    package let pullRequest: Google_Pubsub_V1_PullRequest?
    package let ackRequest: Google_Pubsub_V1_AcknowledgeRequest?
    package let modAckRequest: Google_Pubsub_V1_ModifyAckDeadlineRequest?
    package let streamingFrame: Google_Pubsub_V1_StreamingPullRequest?
    package let canceled: Bool
  }

  package typealias PublishHandler =
    @Sendable (
      Google_Pubsub_V1_PublishRequest, Metadata, Int, ServerContext
    ) async throws -> Google_Pubsub_V1_PublishResponse

  package typealias PullHandler =
    @Sendable (
      Google_Pubsub_V1_PullRequest, Metadata, ServerContext
    ) async throws -> Google_Pubsub_V1_PullResponse

  package typealias AckHandler =
    @Sendable (
      Google_Pubsub_V1_AcknowledgeRequest, Metadata, ServerContext
    ) async throws -> Void

  package typealias ModAckHandler =
    @Sendable (
      Google_Pubsub_V1_ModifyAckDeadlineRequest, Metadata, ServerContext
    ) async throws -> Void

  package typealias StreamingPullHandler = @Sendable (FakeStreamingPullSession) async -> Void

  private struct State: Sendable {
    var nextSeq: Int = 1
    var nextMessageID: Int = 1
    var nextSessionID: Int = 1
    var calls: [CapturedCall] = []
    var sessions: [FakeStreamingPullSession] = []
    var sessionWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var callWaiters:
      [(predicate: @Sendable ([CapturedCall]) -> Bool, cont: CheckedContinuation<Void, Never>)] = []
    var publishHandler: PublishHandler?
    var pullHandler: PullHandler?
    var ackHandler: AckHandler?
    var modAckHandler: ModAckHandler?
    var streamingPullHandler: StreamingPullHandler?
  }

  private let state = Mutex(State())
  private let server: GRPCServer<HTTP2ServerTransport.Posix>
  private let serveTask: Task<Void, any Error>

  package let port: Int
  package var endpoint: String { "http://127.0.0.1:\(self.port)" }
  package var hostPort: String { "127.0.0.1:\(self.port)" }

  private init(
    server: GRPCServer<HTTP2ServerTransport.Posix>,
    serveTask: Task<Void, any Error>,
    port: Int
  ) {
    self.server = server
    self.serveTask = serveTask
    self.port = port
  }

  package static func start() async throws -> FakePubSubServer {
    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: 0),
      transportSecurity: .plaintext,
      config: .defaults {
        $0.compression.enabledAlgorithms = .gzip
        $0.rpc.maxRequestPayloadSize = 20 * 1024 * 1024
        $0.http2.maxHeaderListSize = 4 * 1024 * 1024
      }
    )
    let container = LateRouterService()
    let realServer = GRPCServer(transport: transport, services: [container])
    let task = Task {
      try await realServer.serve()
    }
    let address = try await transport.listeningAddress
    guard let ipv4 = address.ipv4 else {
      task.cancel()
      realServer.beginGracefulShutdown()
      throw PubSubError.invalidConfiguration(description: "Expected IPv4 listening address")
    }
    let instance = FakePubSubServer(server: realServer, serveTask: task, port: ipv4.port)
    container.setOwner(instance)
    return instance
  }

  private final class LateRouterService: RegistrableRPCService, Sendable {
    private final class OwnerBox: Sendable {
      let value = Mutex<FakePubSubServer?>(nil)
    }

    private let ownerBox = OwnerBox()

    func setOwner(_ server: FakePubSubServer) {
      self.ownerBox.value.withLock { $0 = server }
    }

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
      router.registerHandler(
        forMethod: PubSubGRPCDescriptors.publish,
        deserializer: ProtobufDeserializer<Google_Pubsub_V1_PublishRequest>(),
        serializer: ProtobufSerializer<Google_Pubsub_V1_PublishResponse>()
      ) { [ownerBox = self.ownerBox] request, context in
        guard let owner = ownerBox.value.withLock({ $0 }) else {
          return StreamingServerResponse(
            of: Google_Pubsub_V1_PublishResponse.self,
            error: RPCError(code: .unavailable, message: "Server starting")
          )
        }
        return await owner.handlePublish(request: request, context: context)
      }

      router.registerHandler(
        forMethod: PubSubGRPCDescriptors.pull,
        deserializer: ProtobufDeserializer<Google_Pubsub_V1_PullRequest>(),
        serializer: ProtobufSerializer<Google_Pubsub_V1_PullResponse>()
      ) { [ownerBox = self.ownerBox] request, context in
        guard let owner = ownerBox.value.withLock({ $0 }) else {
          return StreamingServerResponse(
            of: Google_Pubsub_V1_PullResponse.self,
            error: RPCError(code: .unavailable, message: "Server starting")
          )
        }
        return await owner.handlePull(request: request, context: context)
      }

      router.registerHandler(
        forMethod: PubSubGRPCDescriptors.acknowledge,
        deserializer: ProtobufDeserializer<Google_Pubsub_V1_AcknowledgeRequest>(),
        serializer: ProtobufSerializer<Google_Protobuf_Empty>()
      ) { [ownerBox = self.ownerBox] request, context in
        guard let owner = ownerBox.value.withLock({ $0 }) else {
          return StreamingServerResponse(
            of: Google_Protobuf_Empty.self,
            error: RPCError(code: .unavailable, message: "Server starting")
          )
        }
        return await owner.handleAck(request: request, context: context)
      }

      router.registerHandler(
        forMethod: PubSubGRPCDescriptors.modifyAckDeadline,
        deserializer: ProtobufDeserializer<Google_Pubsub_V1_ModifyAckDeadlineRequest>(),
        serializer: ProtobufSerializer<Google_Protobuf_Empty>()
      ) { [ownerBox = self.ownerBox] request, context in
        guard let owner = ownerBox.value.withLock({ $0 }) else {
          return StreamingServerResponse(
            of: Google_Protobuf_Empty.self,
            error: RPCError(code: .unavailable, message: "Server starting")
          )
        }
        return await owner.handleModAck(request: request, context: context)
      }

      router.registerHandler(
        forMethod: PubSubGRPCDescriptors.streamingPull,
        deserializer: ProtobufDeserializer<Google_Pubsub_V1_StreamingPullRequest>(),
        serializer: ProtobufSerializer<Google_Pubsub_V1_StreamingPullResponse>()
      ) { [ownerBox = self.ownerBox] request, context in
        guard let owner = ownerBox.value.withLock({ $0 }) else {
          return StreamingServerResponse(
            of: Google_Pubsub_V1_StreamingPullResponse.self,
            error: RPCError(code: .unavailable, message: "Server starting")
          )
        }
        return owner.handleStreamingPull(request: request, context: context)
      }
    }
  }

  package func stop() async {
    let sessions = self.state.withLock { $0.sessions }
    for session in sessions {
      session.close()
    }
    self.server.beginGracefulShutdown()
    self.serveTask.cancel()
    _ = try? await self.serveTask.value
  }

  package func setPublishHandler(_ handler: PublishHandler?) {
    self.state.withLock { $0.publishHandler = handler }
  }

  package func setPullHandler(_ handler: PullHandler?) {
    self.state.withLock { $0.pullHandler = handler }
  }

  package func setAckHandler(_ handler: AckHandler?) {
    self.state.withLock { $0.ackHandler = handler }
  }

  package func setModAckHandler(_ handler: ModAckHandler?) {
    self.state.withLock { $0.modAckHandler = handler }
  }

  package func setStreamingPullHandler(_ handler: StreamingPullHandler?) {
    self.state.withLock { $0.streamingPullHandler = handler }
  }

  package var capturedCalls: [CapturedCall] {
    self.state.withLock { $0.calls }
  }

  package var streamingSessions: [FakeStreamingPullSession] {
    self.state.withLock { $0.sessions }
  }

  package func waitForCalls(atLeast count: Int, method: String? = nil) async {
    await self.waitForCall { calls in
      let matching =
        method == nil
        ? calls.count
        : calls.filter { $0.method == method }.count
      return matching >= count
    }
  }

  package func waitForCall(where predicate: @escaping @Sendable ([CapturedCall]) -> Bool) async {
    await withCheckedContinuation { continuation in
      let met = self.state.withLock { state -> Bool in
        if predicate(state.calls) {
          return true
        }
        state.callWaiters.append((predicate, continuation))
        return false
      }
      if met {
        continuation.resume()
      }
    }
  }

  package func waitForStreamingSession(index: Int = 1) async -> FakeStreamingPullSession {
    await withCheckedContinuation { continuation in
      let met = self.state.withLock { state -> Bool in
        if state.sessions.count >= index {
          return true
        }
        state.sessionWaiters.append((index, continuation))
        return false
      }
      if met {
        continuation.resume()
      }
    }
    return self.state.withLock { $0.sessions[index - 1] }
  }

  package static func makeMetadataDict(_ metadata: Metadata) -> [String: [String]] {
    var dict: [String: [String]] = [:]
    for (key, value) in metadata {
      let stringVal: String
      switch value {
      case .string(let s):
        stringVal = s
      case .binary(let bytes):
        stringVal = Data(bytes).base64EncodedString()
      }
      dict[key.lowercased(), default: []].append(stringVal)
    }
    return dict
  }

  package static func makeEODError(
    code: RPCError.Code = .invalidArgument,
    message: String = "eod error",
    metadata: [String: String]
  ) -> RPCError {
    let status = GoogleRPCStatus(
      code: code,
      message: message,
      details: [
        ErrorDetails.errorInfo(
          reason: "EXACTLY_ONCE_ACKID_FAILURE",
          domain: "pubsub.googleapis.com",
          metadata: metadata
        )
      ]
    )
    return RPCError(code: code, message: message, metadata: status.rpcErrorMetadata)
  }

  private func recordCall(
    method: String,
    metadata: Metadata,
    publishRequest: Google_Pubsub_V1_PublishRequest? = nil,
    pullRequest: Google_Pubsub_V1_PullRequest? = nil,
    ackRequest: Google_Pubsub_V1_AcknowledgeRequest? = nil,
    modAckRequest: Google_Pubsub_V1_ModifyAckDeadlineRequest? = nil,
    streamingFrame: Google_Pubsub_V1_StreamingPullRequest? = nil,
    canceled: Bool = false
  ) -> Int {
    let (seq, waiters) = self.state.withLock {
      state -> (Int, [CheckedContinuation<Void, Never>]) in
      let seq = state.nextSeq
      state.nextSeq += 1
      let call = CapturedCall(
        seq: seq,
        method: method,
        metadata: Self.makeMetadataDict(metadata),
        publishRequest: publishRequest,
        pullRequest: pullRequest,
        ackRequest: ackRequest,
        modAckRequest: modAckRequest,
        streamingFrame: streamingFrame,
        canceled: canceled
      )
      state.calls.append(call)
      var ready: [CheckedContinuation<Void, Never>] = []
      var remaining:
        [(predicate: @Sendable ([CapturedCall]) -> Bool, cont: CheckedContinuation<Void, Never>)] =
          []
      for waiter in state.callWaiters {
        if waiter.predicate(state.calls) {
          ready.append(waiter.cont)
        } else {
          remaining.append(waiter)
        }
      }
      state.callWaiters = remaining
      return (seq, ready)
    }
    for waiter in waiters {
      waiter.resume()
    }
    return seq
  }

  private func nextMessageIDs(count: Int) -> [String] {
    self.state.withLock { state in
      var ids: [String] = []
      ids.reserveCapacity(count)
      for _ in 0..<count {
        ids.append("fake-msg-\(state.nextMessageID)")
        state.nextMessageID += 1
      }
      return ids
    }
  }

  private func handlePublish(
    request: StreamingServerRequest<Google_Pubsub_V1_PublishRequest>,
    context: ServerContext
  ) async -> StreamingServerResponse<Google_Pubsub_V1_PublishResponse> {
    do {
      var iter = request.messages.makeAsyncIterator()
      guard let msg = try await iter.next() else {
        return StreamingServerResponse(
          of: Google_Pubsub_V1_PublishResponse.self,
          error: RPCError(code: .invalidArgument, message: "Missing PublishRequest")
        )
      }
      let seq = self.recordCall(
        method: PubSubGRPCDescriptors.publish.fullyQualifiedMethod,
        metadata: request.metadata,
        publishRequest: msg,
        canceled: context.cancellation.isCancelled
      )
      if let handler = self.state.withLock({ $0.publishHandler }) {
        let resp = try await handler(msg, request.metadata, seq, context)
        return StreamingServerResponse(single: ServerResponse(message: resp))
      }
      let resp = Google_Pubsub_V1_PublishResponse.with {
        $0.messageIds = self.nextMessageIDs(count: msg.messages.count)
      }
      return StreamingServerResponse(single: ServerResponse(message: resp))
    } catch let rpcError as RPCError {
      return StreamingServerResponse(of: Google_Pubsub_V1_PublishResponse.self, error: rpcError)
    } catch let status as GoogleRPCStatus {
      return StreamingServerResponse(
        of: Google_Pubsub_V1_PublishResponse.self,
        error: RPCError(
          code: status.rpcErrorCode,
          message: status.rpcErrorMessage,
          metadata: status.rpcErrorMetadata
        )
      )
    } catch {
      return StreamingServerResponse(
        of: Google_Pubsub_V1_PublishResponse.self,
        error: RPCError(code: .internalError, message: "\(error)")
      )
    }
  }

  private func handlePull(
    request: StreamingServerRequest<Google_Pubsub_V1_PullRequest>,
    context: ServerContext
  ) async -> StreamingServerResponse<Google_Pubsub_V1_PullResponse> {
    do {
      var iter = request.messages.makeAsyncIterator()
      guard let msg = try await iter.next() else {
        return StreamingServerResponse(
          of: Google_Pubsub_V1_PullResponse.self,
          error: RPCError(code: .invalidArgument, message: "Missing PullRequest")
        )
      }
      _ = self.recordCall(
        method: PubSubGRPCDescriptors.pull.fullyQualifiedMethod,
        metadata: request.metadata,
        pullRequest: msg,
        canceled: context.cancellation.isCancelled
      )
      if let handler = self.state.withLock({ $0.pullHandler }) {
        let resp = try await handler(msg, request.metadata, context)
        return StreamingServerResponse(single: ServerResponse(message: resp))
      }
      return StreamingServerResponse(
        single: ServerResponse(message: Google_Pubsub_V1_PullResponse()))
    } catch let rpcError as RPCError {
      return StreamingServerResponse(of: Google_Pubsub_V1_PullResponse.self, error: rpcError)
    } catch {
      return StreamingServerResponse(
        of: Google_Pubsub_V1_PullResponse.self,
        error: RPCError(code: .internalError, message: "\(error)")
      )
    }
  }

  private func handleAck(
    request: StreamingServerRequest<Google_Pubsub_V1_AcknowledgeRequest>,
    context: ServerContext
  ) async -> StreamingServerResponse<Google_Protobuf_Empty> {
    do {
      var iter = request.messages.makeAsyncIterator()
      guard let msg = try await iter.next() else {
        return StreamingServerResponse(
          of: Google_Protobuf_Empty.self,
          error: RPCError(code: .invalidArgument, message: "Missing AcknowledgeRequest")
        )
      }
      _ = self.recordCall(
        method: PubSubGRPCDescriptors.acknowledge.fullyQualifiedMethod,
        metadata: request.metadata,
        ackRequest: msg,
        canceled: context.cancellation.isCancelled
      )
      if let handler = self.state.withLock({ $0.ackHandler }) {
        try await handler(msg, request.metadata, context)
      }
      return StreamingServerResponse(single: ServerResponse(message: Google_Protobuf_Empty()))
    } catch let rpcError as RPCError {
      return StreamingServerResponse(of: Google_Protobuf_Empty.self, error: rpcError)
    } catch let status as GoogleRPCStatus {
      return StreamingServerResponse(
        of: Google_Protobuf_Empty.self,
        error: RPCError(
          code: status.rpcErrorCode,
          message: status.rpcErrorMessage,
          metadata: status.rpcErrorMetadata
        )
      )
    } catch {
      return StreamingServerResponse(
        of: Google_Protobuf_Empty.self,
        error: RPCError(code: .internalError, message: "\(error)")
      )
    }
  }

  private func handleModAck(
    request: StreamingServerRequest<Google_Pubsub_V1_ModifyAckDeadlineRequest>,
    context: ServerContext
  ) async -> StreamingServerResponse<Google_Protobuf_Empty> {
    do {
      var iter = request.messages.makeAsyncIterator()
      guard let msg = try await iter.next() else {
        return StreamingServerResponse(
          of: Google_Protobuf_Empty.self,
          error: RPCError(code: .invalidArgument, message: "Missing ModifyAckDeadlineRequest")
        )
      }
      _ = self.recordCall(
        method: PubSubGRPCDescriptors.modifyAckDeadline.fullyQualifiedMethod,
        metadata: request.metadata,
        modAckRequest: msg,
        canceled: context.cancellation.isCancelled
      )
      if let handler = self.state.withLock({ $0.modAckHandler }) {
        try await handler(msg, request.metadata, context)
      }
      return StreamingServerResponse(single: ServerResponse(message: Google_Protobuf_Empty()))
    } catch let rpcError as RPCError {
      return StreamingServerResponse(of: Google_Protobuf_Empty.self, error: rpcError)
    } catch let status as GoogleRPCStatus {
      return StreamingServerResponse(
        of: Google_Protobuf_Empty.self,
        error: RPCError(
          code: status.rpcErrorCode,
          message: status.rpcErrorMessage,
          metadata: status.rpcErrorMetadata
        )
      )
    } catch {
      return StreamingServerResponse(
        of: Google_Protobuf_Empty.self,
        error: RPCError(code: .internalError, message: "\(error)")
      )
    }
  }

  private func handleStreamingPull(
    request: StreamingServerRequest<Google_Pubsub_V1_StreamingPullRequest>,
    context: ServerContext
  ) -> StreamingServerResponse<Google_Pubsub_V1_StreamingPullResponse> {
    let mdDict = Self.makeMetadataDict(request.metadata)
    let (session, waiters, customHandler) = self.state.withLock {
      state -> (
        FakeStreamingPullSession,
        [CheckedContinuation<Void, Never>],
        StreamingPullHandler?
      ) in
      let id = state.nextSessionID
      state.nextSessionID += 1
      let session = FakeStreamingPullSession(id: id, metadata: mdDict)
      state.sessions.append(session)
      let total = state.sessions.count
      var ready: [CheckedContinuation<Void, Never>] = []
      var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
      for waiter in state.sessionWaiters {
        if total >= waiter.target {
          ready.append(waiter.continuation)
        } else {
          remaining.append(waiter)
        }
      }
      state.sessionWaiters = remaining
      return (session, ready, state.streamingPullHandler)
    }
    for waiter in waiters {
      waiter.resume()
    }
    if let customHandler {
      Task {
        await customHandler(session)
      }
    }

    let requestMetadata = request.metadata
    let inboundMessages = request.messages
    return StreamingServerResponse(metadata: [:]) { writer in
      try await withRPCCancellationHandler {
        let readerTask = Task {
          do {
            for try await frame in inboundMessages {
              _ = self.recordCall(
                method: PubSubGRPCDescriptors.streamingPull.fullyQualifiedMethod,
                metadata: requestMetadata,
                streamingFrame: frame
              )
              session.appendFrame(frame)
            }
          } catch let rpcError as RPCError {
            session.close(error: rpcError)
          } catch {
            session.close(error: RPCError(code: .internalError, message: "\(error)"))
          }
        }
        defer { readerTask.cancel() }
        for await event in session.outboundStream {
          switch event {
          case .response(let response):
            try await writer.write(response)
          case .close(let error):
            if let error {
              throw error
            }
            return
          }
        }
      } onCancelRPC: {
        session.markClientCanceled()
        session.close()
      }
      return [:]
    }
  }
}
