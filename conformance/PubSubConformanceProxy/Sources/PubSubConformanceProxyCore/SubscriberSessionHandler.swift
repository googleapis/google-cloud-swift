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
import GoogleCloudPubSub
import GoogleGax
import Synchronization
import PubSubConformanceProtos
import SwiftProtobuf

enum SubscriberSessionHandler {
  @concurrent
  static func handle(
    request: StreamingServerRequest<Pubsub_Conformance_V1_SubscriberCommand>,
    writer: RPCWriter<Pubsub_Conformance_V1_SubscriberEvent>
  ) async throws {
    var cmdIterator = request.messages.makeAsyncIterator()
    guard let firstCommand = try await cmdIterator.next(),
      case .start(let startCmd) = firstCommand.command
    else {
      throw RPCError(
        code: .invalidArgument,
        message: "Expected StartSubscriberCommand as initial SubscriberCommand."
      )
    }

    let clientOptions: GoogleGax.ClientOptions
    let reqOptions: GoogleGax.RequestOptions
    let subscriberClient: SubscriberClient
    let stream: any MessageStreamProtocol
    let assignedClientID = startCmd.clientID.isEmpty ? UUID().uuidString : startCmd.clientID

    do {
      clientOptions = try ConformanceHelpers.makeClientOptions(
        endpoint: startCmd.endpoint,
        useEmulatorEnv: startCmd.useEmulatorEnv
      )
      reqOptions = try ConformanceHelpers.makeRequestOptions(
        customHeaders: startCmd.customHeaders,
        retryCodes: startCmd.retryCodes,
        hasTotalTimeoutMs: startCmd.hasTotalTimeoutMsCompat,
        totalTimeoutMs: 0,
        hasMaxAttempts: false,
        maxAttempts: 0,
        hasInitialDelayMs: startCmd.hasInitialRetryDelayMs,
        initialDelayMs: startCmd.initialRetryDelayMs,
        hasMaxDelayMs: startCmd.hasMaxRetryDelayMs,
        maxDelayMs: startCmd.maxRetryDelayMs,
        hasMultiplier: startCmd.hasRetryDelayMultiplier,
        multiplier: startCmd.retryDelayMultiplier
      )
      let subClientOptions = SubscriberClientOptions().with {
        $0.client = clientOptions
        $0.projectID = startCmd.projectID.isEmpty ? nil : startCmd.projectID
        $0.subchannelCount = 1
      }
      subscriberClient = try SubscriberClient(subClientOptions)

      let subOptions = SubscribeOptions().with {
        if startCmd.hasNumStreams {
          $0.streamCount = Int(startCmd.numStreams)
        }
        if startCmd.hasMaxOutstandingMessages {
          $0.maxOutstandingMessages = Int(startCmd.maxOutstandingMessages)
        }
        if startCmd.hasMaxOutstandingBytes {
          $0.maxOutstandingBytes = Int(startCmd.maxOutstandingBytes)
        }
        if startCmd.hasEnablePerStreamFlowControl {
          $0.enablePerStreamFlowControl = startCmd.enablePerStreamFlowControl
        }
        if startCmd.hasMaxExtensionMs {
          $0.maxExtension = .milliseconds(startCmd.maxExtensionMs)
        }
        if startCmd.hasMinDurationPerAckExtensionMs {
          $0.minAckExtension = .milliseconds(startCmd.minDurationPerAckExtensionMs)
        }
        if startCmd.hasMaxDurationPerAckExtensionMs {
          $0.maxAckExtension = .milliseconds(startCmd.maxDurationPerAckExtensionMs)
        }
        switch startCmd.shutdownBehavior {
        case .waitForProcessing:
          $0.defaultShutdownBehavior = .waitForProcessing
        case .nackImmediately:
          $0.defaultShutdownBehavior = .nackImmediately
        case .unspecified, .UNRECOGNIZED:
          break
        }
        if startCmd.hasShutdownTimeoutMs {
          $0.defaultShutdownTimeout = .milliseconds(startCmd.shutdownTimeoutMs)
        }
        $0.clientID = assignedClientID
        $0.request = reqOptions
      }

      stream = try subscriberClient.subscribe(
        subscription: startCmd.subscription,
        options: subOptions
      )
    } catch {
      throw RPCError(code: .invalidArgument, message: "\(error)")
    }

    let coordinator = SessionCoordinator(
      stream: stream,
      startCmd: startCmd,
      assignedClientID: assignedClientID,
      writer: writer
    )
    let (writerTask, deliveryTask) = coordinator.start()
    var stopTasks: [Task<Void, Never>] = []
    while let cmd = try? await cmdIterator.next() {
      coordinator.processCommand(cmd, stopTasks: &stopTasks)
    }
    try await coordinator.finish(
      stopTasks: stopTasks,
      deliveryTask: deliveryTask,
      writerTask: writerTask
    )
    _ = subscriberClient
  }
}

extension Pubsub_Conformance_V1_StartSubscriberCommand {
  fileprivate var hasTotalTimeoutMsCompat: Bool { false }
}

private final class SessionCoordinator: Sendable {
  private struct State: Sendable {
    var nextTokenSeq: UInt64 = 1
    var totalDelivered: Int64 = 0
    var activeCallbacks: Int32 = 0
    var heldMessages: [String: ReceivedMessage] = [:]
    var pendingResultCount: Int = 0
    var stopStarted: Bool = false
    var stopCompleted: Bool = false
    var deliveryCompleted: Bool = false
    var stoppedEmitted: Bool = false
    var streamError: (code: Int32, message: String)?
    var pendingResultWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let stream: any MessageStreamProtocol
  private let startCmd: Pubsub_Conformance_V1_StartSubscriberCommand
  private let assignedClientID: String
  private let outbound = AsyncStream.makeStream(of: Pubsub_Conformance_V1_SubscriberEvent.self)
  private let writer: RPCWriter<Pubsub_Conformance_V1_SubscriberEvent>
  private let state = Mutex(State())

  init(
    stream: any MessageStreamProtocol,
    startCmd: Pubsub_Conformance_V1_StartSubscriberCommand,
    assignedClientID: String,
    writer: RPCWriter<Pubsub_Conformance_V1_SubscriberEvent>
  ) {
    self.stream = stream
    self.startCmd = startCmd
    self.assignedClientID = assignedClientID
    self.writer = writer
  }

  func start() -> (writerTask: Task<Void, any Error>, deliveryTask: Task<Void, Never>) {
    let writerTask = Task<Void, any Error> { [outbound, writer] in
      for await event in outbound.stream {
        try await writer.write(event)
      }
    }

    var started = Pubsub_Conformance_V1_StartedEvent()
    started.clientID = self.assignedClientID
    self.emit(.with { $0.started = started })

    let deliveryTask = Task {
      await self.runDeliveryLoop()
    }
    return (writerTask, deliveryTask)
  }

  func processCommand(
    _ cmd: Pubsub_Conformance_V1_SubscriberCommand,
    stopTasks: inout [Task<Void, Never>]
  ) {
    switch cmd.command {
    case .settle(let settleCmd):
      self.handleSettleCommand(settleCmd, taskCollector: &stopTasks)
    case .stop(let stopCmd):
      let stopTask = self.triggerStop(stopCmd: stopCmd)
      stopTasks.append(stopTask)
    case .start, .none:
      break
    }
  }

  func finish(
    stopTasks: [Task<Void, Never>],
    deliveryTask: Task<Void, Never>,
    writerTask: Task<Void, any Error>
  ) async throws {
    var allStopTasks = stopTasks
    // Ensure session stops cleanly if harness closed command stream without StopSubscriberCommand.
    let needImplicitStop = self.state.withLock { !$0.stopStarted }
    if needImplicitStop {
      let implicitTask = self.triggerStop(stopCmd: nil)
      allStopTasks.append(implicitTask)
    }

    for task in allStopTasks {
      await task.value
    }
    await deliveryTask.value
    await self.awaitPendingResultsAndEmitStopped()
    self.outbound.continuation.finish()
    try await writerTask.value
  }

  private func emit(_ event: Pubsub_Conformance_V1_SubscriberEvent) {
    self.outbound.continuation.yield(event)
  }

  private func runDeliveryLoop() async {
    do {
      for try await received in self.stream {
        let mode = self.startCmd.autoSettleMode
        let isAutoWithResult =
          (mode == .autoAckWithResult || mode == .autoNackWithResult)

        let (token, activeCount): (String, Int32) = self.state.withLock { state in
          let id = "del-\(state.nextTokenSeq)"
          state.nextTokenSeq += 1
          state.totalDelivered += 1
          let keepsCallbackActive: Bool
          switch mode {
          case .unspecified, .interactive:
            state.heldMessages[id] = received
            keepsCallbackActive = true
          case .autoAckWithResult, .autoNackWithResult:
            state.pendingResultCount += 1
            keepsCallbackActive = true
          case .autoAck, .autoNack, .autoDropWithoutSettle, .UNRECOGNIZED:
            keepsCallbackActive = false
          }
          if keepsCallbackActive {
            state.activeCallbacks += 1
          }
          return (id, keepsCallbackActive ? state.activeCallbacks : max(state.activeCallbacks, 1))
        }

        var delivered = Pubsub_Conformance_V1_MessageDeliveredEvent()
        delivered.deliveryToken = token
        delivered.messageID = received.message.messageID
        delivered.data = received.message.data
        delivered.attributes = received.message.attributes
        delivered.orderingKey = received.message.orderingKey
        if let publishTime = received.message.publishTime {
          delivered.publishTime = ConformanceHelpers.toProtoTimestamp(publishTime)
        }
        if let attempt = received.message.deliveryAttempt {
          delivered.deliveryAttempt = Int32(attempt)
          delivered.hasDeliveryAttempt_p = true
        }
        delivered.activeCallbacks = activeCount
        delivered.isExactlyOnce = received.isExactlyOnce
        delivered.autoSettled = isAutoWithResult
        self.emit(.with { $0.messageDelivered = delivered })

        switch mode {
        case .unspecified, .interactive:
          break
        case .autoAck:
          received.ack()
        case .autoNack:
          received.nack()
        case .autoDropWithoutSettle:
          break
        case .autoAckWithResult:
          Task {
            await self.runConfirmedSettlement(received: received, token: token, isNack: false)
          }
        case .autoNackWithResult:
          Task {
            await self.runConfirmedSettlement(received: received, token: token, isNack: true)
          }
        case .UNRECOGNIZED:
          break
        }
      }
    } catch {
      let mapped = ConformanceHelpers.mapErrorToGRPC(error)
      self.state.withLock { state in
        if state.streamError == nil {
          state.streamError = mapped
        }
      }
    }

    self.state.withLock { state in
      state.deliveryCompleted = true
    }
    self.tryEmitStoppedIfReady()
  }

  private func handleSettleCommand(
    _ settleCmd: Pubsub_Conformance_V1_SettleMessageCommand,
    taskCollector: inout [Task<Void, Never>]
  ) {
    let token = settleCmd.deliveryToken
    let action = settleCmd.action
    let needsAsyncResult = (action == .ackWithResult || action == .nackWithResult)

    let held: ReceivedMessage? = self.state.withLock { state in
      guard let msg = state.heldMessages.removeValue(forKey: token) else {
        return nil
      }
      if needsAsyncResult {
        state.pendingResultCount += 1
      } else {
        state.activeCallbacks = max(0, state.activeCallbacks - 1)
      }
      return msg
    }

    guard let msg = held else {
      return
    }

    switch action {
    case .ack:
      msg.ack()
    case .nack:
      msg.nack()
    case .returnWithoutSettle, .unspecified, .UNRECOGNIZED:
      // Leaving scope drops `msg` immediately without calling ack/nack (`LEASE-05`).
      break
    case .ackWithResult:
      let t = Task {
        await self.runConfirmedSettlement(received: msg, token: token, isNack: false)
      }
      taskCollector.append(t)
    case .nackWithResult:
      let t = Task {
        await self.runConfirmedSettlement(received: msg, token: token, isNack: true)
      }
      taskCollector.append(t)
    }
  }

  private func runConfirmedSettlement(
    received: ReceivedMessage,
    token: String,
    isNack: Bool
  ) async {
    var event = Pubsub_Conformance_V1_SettlementResultEvent()
    event.deliveryToken = token
    event.isNack = isNack
    do {
      let result = isNack ? try await received.nackWithResult() : try await received.ackWithResult()
      event.status = ConformanceHelpers.mapSettlementStatus(result.status)
      event.grpcErrorCode = 0
    } catch {
      let mapped = ConformanceHelpers.mapSettlementError(error)
      event.status = mapped.status
      event.grpcErrorCode = mapped.grpcCode
      event.errorMessage = mapped.message
    }
    self.emit(.with { $0.settlementResult = event })

    let waitersToResume: [CheckedContinuation<Void, Never>] = self.state.withLock { state in
      state.activeCallbacks = max(0, state.activeCallbacks - 1)
      state.pendingResultCount = max(0, state.pendingResultCount - 1)
      guard state.pendingResultCount == 0 else {
        return []
      }
      let out = state.pendingResultWaiters
      state.pendingResultWaiters.removeAll()
      return out
    }
    for waiter in waitersToResume {
      waiter.resume()
    }
    self.tryEmitStoppedIfReady()
  }

  private func triggerStop(
    stopCmd: Pubsub_Conformance_V1_StopSubscriberCommand?
  ) -> Task<Void, Never> {
    self.state.withLock { state in
      state.stopStarted = true
    }

    var options = SubscriberShutdownOptions()
    if let stopCmd {
      switch stopCmd.shutdownBehavior {
      case .waitForProcessing:
        options.behavior = .waitForProcessing
      case .nackImmediately:
        options.behavior = .nackImmediately
      case .unspecified, .UNRECOGNIZED:
        break
      }
      if stopCmd.hasShutdownTimeoutMs {
        options.timeout = .milliseconds(max(0, stopCmd.shutdownTimeoutMs))
      }
    }

    return Task {
      do {
        _ = try await self.stream.stop(options: options)
      } catch {
        let mapped = ConformanceHelpers.mapErrorToGRPC(error)
        self.state.withLock { state in
          if state.streamError == nil {
            state.streamError = mapped
          }
        }
      }
      self.state.withLock { state in
        state.stopCompleted = true
      }
      self.tryEmitStoppedIfReady()
    }
  }

  private func tryEmitStoppedIfReady() {
    let stoppedEvent: Pubsub_Conformance_V1_StoppedEvent? = self.state.withLock { state in
      guard state.deliveryCompleted && state.pendingResultCount == 0 && !state.stoppedEmitted else {
        return nil
      }
      guard state.stopCompleted || state.streamError != nil else {
        return nil
      }
      state.stoppedEmitted = true
      state.heldMessages.removeAll()
      var ev = Pubsub_Conformance_V1_StoppedEvent()
      ev.totalDelivered = state.totalDelivered
      if let err = state.streamError {
        ev.errorCode = err.code
        ev.errorMessage = err.message
      }
      return ev
    }
    if let stoppedEvent {
      self.emit(.with { $0.stopped = stoppedEvent })
    }
  }

  private func awaitPendingResultsAndEmitStopped() async {
    await withCheckedContinuation { continuation in
      let done = self.state.withLock { state -> Bool in
        if state.pendingResultCount == 0 {
          return true
        }
        state.pendingResultWaiters.append(continuation)
        return false
      }
      if done {
        continuation.resume()
      }
    }

    let finalStopped: Pubsub_Conformance_V1_StoppedEvent? = self.state.withLock { state in
      guard !state.stoppedEmitted else {
        return nil
      }
      state.stoppedEmitted = true
      state.heldMessages.removeAll()
      var ev = Pubsub_Conformance_V1_StoppedEvent()
      ev.totalDelivered = state.totalDelivered
      if let err = state.streamError {
        ev.errorCode = err.code
        ev.errorMessage = err.message
      }
      return ev
    }
    if let finalStopped {
      self.emit(.with { $0.stopped = finalStopped })
    }
  }
}
