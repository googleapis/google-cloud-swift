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
public import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import GoogleAuth
import GoogleCloudPubSub
import GoogleGax
import Synchronization
import PubSubConformanceProtos
import SwiftProtobuf

public final class PubSubProxyService: RegistrableRPCService, Sendable {
  private struct PublisherEntry: Sendable {
    let publisher: Publisher
    let topic: String
    let blockingOptions: BlockingPublisherClientOptions
    let blockingRequestOptions: GoogleGax.RequestOptions
    var blockingClient: BlockingPublisherClient?
    var isStopped: Bool = false
    var nextTokenSeq: UInt64 = 1
    var pendingHandles: [String: PublishHandle] = [:]
  }

  private struct State: Sendable {
    var nextPublisherSeq: UInt64 = 1
    var publishers: [String: PublisherEntry] = [:]
  }

  private static let serviceDescriptor = ServiceDescriptor(
    fullyQualifiedService: "pubsub.conformance.v1.PubSubProxy"
  )

  private let state = Mutex(State())
  private let onShutdownRequested: @Sendable () -> Void

  public init(onShutdownRequested: @escaping @Sendable () -> Void = {}) {
    self.onShutdownRequested = onShutdownRequested
  }

  public func registerMethods<Transport: ServerTransport>(
    with router: inout RPCRouter<Transport>
  ) {
    self.registerUnary(router: &router, method: "GetCapabilities") {
      (_: Pubsub_Conformance_V1_GetCapabilitiesRequest) in
      CapabilitiesBuilder.buildResponse()
    }

    self.registerUnary(router: &router, method: "ResetTraces") {
      (_: Pubsub_Conformance_V1_ResetTracesRequest) in
      Pubsub_Conformance_V1_ResetTracesResponse()
    }

    self.registerUnary(router: &router, method: "DrainTraces") {
      (_: Pubsub_Conformance_V1_DrainTracesRequest) in
      Pubsub_Conformance_V1_DrainTracesResponse()
    }

    self.registerUnary(router: &router, method: "CreatePublisher") {
      (req: Pubsub_Conformance_V1_CreatePublisherRequest) in
      try self.handleCreatePublisher(req)
    }

    self.registerUnary(router: &router, method: "Publish") {
      (req: Pubsub_Conformance_V1_PublishRequest) in
      await self.handlePublish(req)
    }

    self.registerUnary(router: &router, method: "AwaitPublish") {
      (req: Pubsub_Conformance_V1_AwaitPublishRequest) in
      await self.handleAwaitPublish(req)
    }

    self.registerUnary(router: &router, method: "FlushPublisher") {
      (req: Pubsub_Conformance_V1_FlushPublisherRequest) in
      try await self.handleFlushPublisher(req)
    }

    self.registerUnary(router: &router, method: "StopPublisher") {
      (req: Pubsub_Conformance_V1_StopPublisherRequest) in
      try await self.handleStopPublisher(req)
    }

    self.registerUnary(router: &router, method: "ResumePublish") {
      (req: Pubsub_Conformance_V1_ResumePublishRequest) in
      try await self.handleResumePublish(req)
    }

    self.registerUnary(router: &router, method: "ClosePublisher") {
      (req: Pubsub_Conformance_V1_ClosePublisherRequest) in
      try await self.handleClosePublisher(req)
    }

    self.registerUnary(router: &router, method: "UnaryPull") {
      (req: Pubsub_Conformance_V1_UnaryPullRequest) in
      await self.handleUnaryPull(req)
    }

    self.registerUnary(router: &router, method: "ShutdownProxy") {
      (req: Pubsub_Conformance_V1_ShutdownProxyRequest) in
      self.handleShutdownProxy(req)
    }

    router.registerHandler(
      forMethod: MethodDescriptor(service: Self.serviceDescriptor, method: "SubscriberSession"),
      deserializer: ProtobufDeserializer<Pubsub_Conformance_V1_SubscriberCommand>(),
      serializer: ProtobufSerializer<Pubsub_Conformance_V1_SubscriberEvent>()
    ) { request, _ in
      StreamingServerResponse(metadata: [:]) { writer in
        try await SubscriberSessionHandler.handle(request: request, writer: writer)
        return [:]
      }
    }
  }

  private func registerUnary<
    Transport: ServerTransport,
    Req: SwiftProtobuf.Message & Sendable,
    Resp: SwiftProtobuf.Message & Sendable
  >(
    router: inout RPCRouter<Transport>,
    method: String,
    handler: @escaping @Sendable (Req) async throws -> Resp
  ) {
    let descriptor = MethodDescriptor(service: Self.serviceDescriptor, method: method)
    router.registerHandler(
      forMethod: descriptor,
      deserializer: ProtobufDeserializer<Req>(),
      serializer: ProtobufSerializer<Resp>()
    ) { request, _ in
      var iter = request.messages.makeAsyncIterator()
      guard let first = try await iter.next() else {
        return StreamingServerResponse(
          of: Resp.self,
          error: RPCError(code: .invalidArgument, message: "Missing request for \(method).")
        )
      }
      // Drain request stream so grpc-swift-nio-transport does not emit RST_STREAM frames.
      while try await iter.next() != nil {}
      let responseMessage = try await handler(first)
      return StreamingServerResponse(single: ServerResponse(message: responseMessage))
    }
  }

  private func handleCreatePublisher(
    _ req: Pubsub_Conformance_V1_CreatePublisherRequest
  ) throws -> Pubsub_Conformance_V1_CreatePublisherResponse {
    do {
      let clientOptions = try ConformanceHelpers.makeClientOptions(
        endpoint: req.endpoint,
        useEmulatorEnv: req.useEmulatorEnv
      )
      let requestOptions = try ConformanceHelpers.makeRequestOptions(
        customHeaders: req.customHeaders,
        retryCodes: req.retryCodes,
        hasTotalTimeoutMs: req.hasTotalTimeoutMs,
        totalTimeoutMs: req.totalTimeoutMs,
        hasMaxAttempts: req.hasMaxAttempts,
        maxAttempts: req.maxAttempts,
        hasInitialDelayMs: req.hasInitialRetryDelayMs,
        initialDelayMs: req.initialRetryDelayMs,
        hasMaxDelayMs: req.hasMaxRetryDelayMs,
        maxDelayMs: req.maxRetryDelayMs,
        hasMultiplier: req.hasRetryDelayMultiplier,
        multiplier: req.retryDelayMultiplier
      )
      let projectID: String? = req.projectID.isEmpty ? nil : req.projectID

      let pubClientOptions = PublisherClientOptions().with {
        $0.client = clientOptions
        $0.projectID = projectID
        $0.subchannelCount = 1
      }

      let topicOptions = TopicPublisherOptions().with { opts in
        if req.hasCountThreshold {
          opts.batching.countThreshold = Int(req.countThreshold)
        }
        if req.hasByteThreshold {
          opts.batching.byteThreshold = Int(req.byteThreshold)
        }
        if req.hasDelayThresholdMs {
          opts.batching.delayThreshold = .milliseconds(req.delayThresholdMs)
        }
        if req.hasMaxOutstandingMessages {
          opts.flowControl.maxPendingMessages = Int(req.maxOutstandingMessages)
        }
        if req.hasMaxOutstandingBytes {
          opts.flowControl.maxPendingBytes = Int(req.maxOutstandingBytes)
        }
        switch req.limitExceededBehavior {
        case .ignore:
          opts.flowControl.limitExceededBehavior = .ignore
        case .block:
          opts.flowControl.limitExceededBehavior = .block
        case .signalError:
          opts.flowControl.limitExceededBehavior = .signalError
        case .unspecified, .UNRECOGNIZED:
          break
        }
        if req.hasEnableCompression {
          opts.compression.isEnabled = req.enableCompression
        }
        if req.hasCompressionBytesThreshold {
          opts.compression.bytesThreshold = Int(req.compressionBytesThreshold)
        }
        if req.hasHedging {
          opts.hedging.isEnabled = req.hedging.enabled
          if req.hedging.hasDelayMs {
            opts.hedging.delay = .milliseconds(req.hedging.delayMs)
          }
          if req.hedging.hasMaxTokens {
            opts.hedging.maxTokens = Int(req.hedging.maxTokens)
          }
          if req.hedging.hasRefillRatio {
            opts.hedging.refillRatio = req.hedging.refillRatio
          }
        }
        opts.request = requestOptions
      }

      let publisher = try Publisher(
        topic: req.topic,
        clientOptions: pubClientOptions,
        options: topicOptions
      )

      let blockingOptions = BlockingPublisherClientOptions().with {
        $0.client = clientOptions
        $0.projectID = projectID
        $0.subchannelCount = 1
        $0.compression = topicOptions.compression
      }

      let id = self.state.withLock { state -> String in
        let assigned = "pub-\(state.nextPublisherSeq)"
        state.nextPublisherSeq += 1
        state.publishers[assigned] = PublisherEntry(
          publisher: publisher,
          topic: req.topic,
          blockingOptions: blockingOptions,
          blockingRequestOptions: requestOptions
        )
        return assigned
      }

      var response = Pubsub_Conformance_V1_CreatePublisherResponse()
      response.publisherID = id
      return response
    } catch {
      let (rawCode, message) = ConformanceHelpers.mapErrorToGRPC(error)
      throw RPCError(code: Self.rpcErrorCode(from: rawCode), message: message)
    }
  }

  private func handlePublish(
    _ req: Pubsub_Conformance_V1_PublishRequest
  ) async -> Pubsub_Conformance_V1_PublishResponse {
    var response = Pubsub_Conformance_V1_PublishResponse()

    let entry = self.state.withLock { $0.publishers[req.publisherID] }
    guard let entry else {
      response.errorCode = 9  // FAILED_PRECONDITION
      response.errorMessage = "Publisher '\(req.publisherID)' is closed or unknown."
      return response
    }

    var mergedAttributes = req.attributes
    if !req.rawAttributes.isEmpty {
      do {
        for raw in req.rawAttributes {
          guard let key = String(validating: raw.key, as: UTF8.self) else {
            throw PubSubError.invalidUTF8Attribute(
              description: "Message attribute key contains invalid UTF-8 bytes."
            )
          }
          guard let val = String(validating: raw.value, as: UTF8.self) else {
            throw PubSubError.invalidUTF8Attribute(
              description: "Message attribute value contains invalid UTF-8 bytes."
            )
          }
          mergedAttributes[key] = val
        }
      } catch {
        let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
        response.errorCode = code
        response.errorMessage = msg
        return response
      }
    }

    let message = Message(
      data: req.data,
      attributes: mergedAttributes,
      orderingKey: req.orderingKey
    )

    if req.verifyAttributesImmutability {
      response.callerAttributesMutated = (mergedAttributes != message.attributes)
    }

    if req.useBlockingPublisher {
      do {
        let blockingClient = try self.getOrCreateBlockingClient(for: req.publisherID)
        let publishOptions = BlockingPublishOptions().with {
          $0.request = entry.blockingRequestOptions
        }
        let result = try await blockingClient.publish(
          message,
          topic: entry.topic,
          options: publishOptions
        )
        response.messageID = result.messageID
      } catch {
        let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
        response.errorCode = code
        response.errorMessage = msg
      }
      return response
    }

    if req.asyncFire {
      do {
        let handle = try await entry.publisher.startPublish(message)
        let token = self.state.withLock { state -> String? in
          guard var current = state.publishers[req.publisherID] else {
            return nil
          }
          let tok = "tok-\(current.nextTokenSeq)"
          current.nextTokenSeq += 1
          current.pendingHandles[tok] = handle
          state.publishers[req.publisherID] = current
          return tok
        }
        guard let token else {
          response.errorCode = 9
          response.errorMessage = "Publisher '\(req.publisherID)' closed while publishing."
          return response
        }
        response.publishToken = token
      } catch {
        let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
        response.errorCode = code
        response.errorMessage = msg
      }
      return response
    }

    do {
      let result = try await entry.publisher.publish(message)
      response.messageID = result.messageID
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      response.errorCode = code
      response.errorMessage = msg
    }
    return response
  }

  private func getOrCreateBlockingClient(for publisherID: String) throws -> BlockingPublisherClient
  {
    if let existing = self.state.withLock({ $0.publishers[publisherID]?.blockingClient }) {
      return existing
    }
    guard let config = self.state.withLock({ $0.publishers[publisherID]?.blockingOptions })
    else {
      throw PubSubError.publisherShutDown
    }
    let created = try BlockingPublisherClient(config)
    return self.state.withLock { state in
      if let existing = state.publishers[publisherID]?.blockingClient {
        return existing
      }
      state.publishers[publisherID]?.blockingClient = created
      return created
    }
  }

  private func handleAwaitPublish(
    _ req: Pubsub_Conformance_V1_AwaitPublishRequest
  ) async -> Pubsub_Conformance_V1_PublishResponse {
    var response = Pubsub_Conformance_V1_PublishResponse()
    let handle = self.state.withLock { state -> PublishHandle? in
      guard var entry = state.publishers[req.publisherID] else {
        return nil
      }
      let h = entry.pendingHandles.removeValue(forKey: req.publishToken)
      state.publishers[req.publisherID] = entry
      return h
    }
    guard let handle else {
      response.errorCode = 5  // NOT_FOUND
      response.errorMessage = "Publish token '\(req.publishToken)' not found."
      return response
    }
    do {
      let result = try await handle.result()
      response.messageID = result.messageID
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      response.errorCode = code
      response.errorMessage = msg
    }
    return response
  }

  private func handleFlushPublisher(
    _ req: Pubsub_Conformance_V1_FlushPublisherRequest
  ) async throws -> Pubsub_Conformance_V1_FlushPublisherResponse {
    guard let entry = self.state.withLock({ $0.publishers[req.publisherID] }) else {
      throw RPCError(code: .notFound, message: "Publisher '\(req.publisherID)' not found.")
    }
    do {
      _ = try await entry.publisher.flush()
      return Pubsub_Conformance_V1_FlushPublisherResponse()
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      throw RPCError(code: Self.rpcErrorCode(from: code), message: msg)
    }
  }

  private func handleStopPublisher(
    _ req: Pubsub_Conformance_V1_StopPublisherRequest
  ) async throws -> Pubsub_Conformance_V1_StopPublisherResponse {
    guard let entry = self.state.withLock({ $0.publishers[req.publisherID] }) else {
      throw RPCError(code: .notFound, message: "Publisher '\(req.publisherID)' not found.")
    }
    do {
      _ = try await entry.publisher.shutdown()
      self.state.withLock { $0.publishers[req.publisherID]?.isStopped = true }
      return Pubsub_Conformance_V1_StopPublisherResponse()
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      throw RPCError(code: Self.rpcErrorCode(from: code), message: msg)
    }
  }

  private func handleResumePublish(
    _ req: Pubsub_Conformance_V1_ResumePublishRequest
  ) async throws -> Pubsub_Conformance_V1_ResumePublishResponse {
    guard let entry = self.state.withLock({ $0.publishers[req.publisherID] }) else {
      throw RPCError(code: .notFound, message: "Publisher '\(req.publisherID)' not found.")
    }
    do {
      _ = try await entry.publisher.resumePublishing(orderingKey: req.orderingKey)
      return Pubsub_Conformance_V1_ResumePublishResponse()
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      throw RPCError(code: Self.rpcErrorCode(from: code), message: msg)
    }
  }

  private func handleClosePublisher(
    _ req: Pubsub_Conformance_V1_ClosePublisherRequest
  ) async throws -> Pubsub_Conformance_V1_ClosePublisherResponse {
    let removed = self.state.withLock { $0.publishers.removeValue(forKey: req.publisherID) }
    if let removed, !removed.isStopped {
      _ = try? await removed.publisher.shutdown()
    }
    return Pubsub_Conformance_V1_ClosePublisherResponse()
  }

  private func handleUnaryPull(
    _ req: Pubsub_Conformance_V1_UnaryPullRequest
  ) async -> Pubsub_Conformance_V1_UnaryPullResponse {
    var response = Pubsub_Conformance_V1_UnaryPullResponse()
    do {
      let clientOptions = try ConformanceHelpers.makeClientOptions(
        endpoint: req.endpoint,
        useEmulatorEnv: req.useEmulatorEnv
      )
      let reqOptions = try ConformanceHelpers.makeRequestOptions(
        customHeaders: req.customHeaders,
        retryCodes: req.retryCodes,
        hasTotalTimeoutMs: req.hasTotalTimeoutMs,
        totalTimeoutMs: req.totalTimeoutMs,
        hasMaxAttempts: req.hasMaxAttempts,
        maxAttempts: req.maxAttempts,
        hasInitialDelayMs: req.hasInitialRetryDelayMs,
        initialDelayMs: req.initialRetryDelayMs,
        hasMaxDelayMs: req.hasMaxRetryDelayMs,
        maxDelayMs: req.maxRetryDelayMs,
        hasMultiplier: req.hasRetryDelayMultiplier,
        multiplier: req.retryDelayMultiplier
      )
      let subClientOptions = SubscriberClientOptions().with {
        $0.client = clientOptions
        $0.projectID = req.projectID.isEmpty ? nil : req.projectID
        $0.subchannelCount = 1
      }
      let client = try SubscriberClient(subClientOptions)
      let pullOptions = PullOptions().with { opts in
        opts.maxMessages = Int(req.maxMessages)
        opts.returnImmediately = req.returnImmediately
        if req.hasMaxExtensionMs {
          opts.maxExtension = .milliseconds(req.maxExtensionMs)
        }
        if req.hasMinDurationPerAckExtensionMs {
          opts.minAckExtension = .milliseconds(req.minDurationPerAckExtensionMs)
        }
        if req.hasMaxDurationPerAckExtensionMs {
          opts.maxAckExtension = .milliseconds(req.maxDurationPerAckExtensionMs)
        }
        opts.request = reqOptions
      }

      var pulledMessages: [Pubsub_Conformance_V1_UnaryPullResponse.PulledMessage] = []
      var hadPulledMessages = false
      do {
        let pullResult = try await client.pull(
          subscription: req.subscription,
          options: pullOptions
        )
        if req.hasLeaseExtensionMs && req.leaseExtensionMs > 0 {
          try? await Task.sleep(for: .milliseconds(req.leaseExtensionMs))
        }

        hadPulledMessages = !pullResult.messages.isEmpty
        pulledMessages.reserveCapacity(pullResult.messages.count)
        for received in pullResult.messages {
          var pm = Pubsub_Conformance_V1_UnaryPullResponse.PulledMessage()
          pm.messageID = received.message.messageID
          pm.data = received.message.data
          pm.attributes = received.message.attributes
          pm.orderingKey = received.message.orderingKey
          if let publishTime = received.message.publishTime {
            pm.publishTime = ConformanceHelpers.toProtoTimestamp(publishTime)
          }
          if let attempt = received.message.deliveryAttempt {
            pm.deliveryAttempt = Int32(attempt)
            pm.hasDeliveryAttempt_p = true
          }

          switch req.settleAction {
          case .ack, .ackWithResult:
            do {
              let res = try await received.ackWithResult()
              pm.settleStatus = ConformanceHelpers.mapSettlementStatus(res.status)
              pm.settleErrorCode = 0
            } catch {
              let mapped = ConformanceHelpers.mapSettlementError(error)
              pm.settleStatus = mapped.status
              pm.settleErrorCode = mapped.grpcCode
              pm.settleErrorMessage = mapped.message
            }
          case .nack, .nackWithResult:
            do {
              let res = try await received.nackWithResult()
              pm.settleStatus = ConformanceHelpers.mapSettlementStatus(res.status)
              pm.settleErrorCode = 0
            } catch {
              let mapped = ConformanceHelpers.mapSettlementError(error)
              pm.settleStatus = mapped.status
              pm.settleErrorCode = mapped.grpcCode
              pm.settleErrorMessage = mapped.message
            }
          case .returnWithoutSettle, .unspecified, .UNRECOGNIZED:
            pm.settleStatus = .unspecified
          }
          pulledMessages.append(pm)
        }
      }
      if req.settleAction == .returnWithoutSettle && hadPulledMessages {
        // Allow ARC deinit auto-nack batcher (5ms coalesce) to flush before returning.
        try? await Task.sleep(for: .milliseconds(30))
      }
      response.messages = pulledMessages
    } catch {
      let (code, msg) = ConformanceHelpers.mapErrorToGRPC(error)
      response.errorCode = code
      response.errorMessage = msg
    }
    return response
  }

  private func handleShutdownProxy(
    _ req: Pubsub_Conformance_V1_ShutdownProxyRequest
  ) -> Pubsub_Conformance_V1_ShutdownProxyResponse {
    let delayMs = min(max(req.gracePeriodMs, 10), 250)
    let onShutdown = self.onShutdownRequested
    Task {
      try? await Task.sleep(for: .milliseconds(delayMs))
      onShutdown()
    }
    return Pubsub_Conformance_V1_ShutdownProxyResponse()
  }

  private static func rpcErrorCode(from raw: Int32) -> RPCError.Code {
    Status.Code(rawValue: Int(raw)).flatMap { RPCError.Code($0) } ?? .unknown
  }
}
