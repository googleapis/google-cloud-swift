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
package import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
package import GoogleAuth
@_spi(GoogleCloudInternal) package import GoogleGax
import GoogleRpc
import GoogleWKT
@_spi(GoogleCloudInternal) import GoogleWKTConvert
import Logging
import Synchronization
package import SwiftProtobuf

package enum PubSubGRPCDescriptors {
  private static let publisherService = ServiceDescriptor(
    fullyQualifiedService: "google.pubsub.v1.Publisher"
  )
  private static let subscriberService = ServiceDescriptor(
    fullyQualifiedService: "google.pubsub.v1.Subscriber"
  )

  package static let publish = MethodDescriptor(
    service: publisherService,
    method: "Publish"
  )
  package static let pull = MethodDescriptor(
    service: subscriberService,
    method: "Pull"
  )
  package static let acknowledge = MethodDescriptor(
    service: subscriberService,
    method: "Acknowledge"
  )
  package static let modifyAckDeadline = MethodDescriptor(
    service: subscriberService,
    method: "ModifyAckDeadline"
  )
  package static let streamingPull = MethodDescriptor(
    service: subscriberService,
    method: "StreamingPull"
  )
}

package final class GRPCChannelPool: Sendable {
  package static let defaultEndpoint = "https://pubsub.googleapis.com"
  package static let defaultMaxMessageBytes = 20 * 1024 * 1024
  package static let defaultMaxMetadataBytes = 4 * 1024 * 1024

  private struct ChannelEntry: Sendable {
    let client: GRPCClient<HTTP2ClientTransport.Posix>
    let task: Task<Void, any Error>
  }

  private let channels: [ChannelEntry]
  private let nextIndex = Atomic<UInt64>(0)
  private let shutdownState = Atomic<Bool>(false)

  package let credentials: GoogleAuth.Credentials
  package let quotaProject: String?
  package let universeDomain: String
  package let isEmulator: Bool
  package let authority: String
  package let targetHost: String
  package let targetPort: Int
  package let defaultAttemptTimeout: Duration?
  package let defaultRetryThrottler: any GoogleGax.RetryThrottler
  package let clientHeader: _ApiClientHeader
  private let apiClientHeaderValue: String
  package let pubSubLogger: PubSubLogger

  package var subchannelCount: Int { self.channels.count }

  package convenience init(
    from options: ClientOptions,
    subchannelCount: Int
  ) throws {
    try self.init(
      from: options,
      subchannelCount: subchannelCount,
      environment: ProcessInfo.processInfo.environment
    )
  }

  package init(
    from options: ClientOptions,
    subchannelCount: Int,
    environment: [String: String]
  ) throws {
    if subchannelCount < 1 {
      throw PubSubError.invalidConfiguration(
        description: "subchannelCount (\(subchannelCount)) must be >= 1.")
    }

    let resolvedEmulator = _Host.resolveEmulatorEndpoint(
      endpoint: options.endpoint,
      emulatorEnvironmentVariable: "PUBSUB_EMULATOR_HOST",
      environment: environment
    )
    let effectiveEndpoint =
      resolvedEmulator.isEmulator ? resolvedEmulator.endpoint : options.endpoint
    self.isEmulator = resolvedEmulator.isEmulator
    let universeDomain = _Host.resolveUniverseDomain(options: options, environment: environment)
    self.universeDomain = universeDomain

    if let credentials = options.credentials {
      self.credentials = credentials
    } else if resolvedEmulator.isEmulator {
      self.credentials = try GoogleAuth.Credentials(configuration: .anonymous)
    } else {
      self.credentials = try GoogleAuth.Credentials()
    }

    self.quotaProject = options.quotaProject
    self.defaultAttemptTimeout = options.attemptTimeout
    self.defaultRetryThrottler = options.retryThrottler
    self.pubSubLogger = PubSubLogger(options.logger)

    var header = _ApiClientHeader.veneer(packageVersion: PackageVersion.version)
    header.setToken(.grpc, version: "2.4.4")
    header.setToken(.protobuf, version: SwiftProtobuf.Version.versionString)
    self.clientHeader = header
    self.apiClientHeaderValue = header.build()

    let rawEndpoint = try _Host.endpoint(
      endpoint: effectiveEndpoint,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain
    )
    let endpointWithScheme = rawEndpoint.contains("://") ? rawEndpoint : "https://\(rawEndpoint)"
    guard let components = URLComponents(string: endpointWithScheme),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = components.host, !host.isEmpty
    else {
      throw ClientError.invalidEndpoint(rawEndpoint)
    }

    let isSecure = scheme == "https"
    let port = components.port ?? (isSecure ? 443 : 80)
    let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity =
      isSecure ? .tls : .plaintext
    let authority = try _Host.authority(
      endpoint: effectiveEndpoint,
      defaultEndpoint: Self.defaultEndpoint,
      universeDomain: universeDomain
    )
    self.targetHost = host
    self.targetPort = port
    self.authority = authority

    var builtChannels: [ChannelEntry] = []
    builtChannels.reserveCapacity(subchannelCount)
    do {
      for _ in 0..<subchannelCount {
        let transport = try HTTP2ClientTransport.Posix(
          target: .dns(host: host, port: port),
          transportSecurity: transportSecurity,
          config: .defaults {
            $0.http2.authority = authority
            $0.http2.maxHeaderListSize = Self.defaultMaxMetadataBytes
            $0.compression.enabledAlgorithms = .gzip
          },
          serviceConfig: ServiceConfig(loadBalancingConfig: [.roundRobin])
        )
        let client = GRPCClient(transport: transport)
        let task = Task {
          try await client.runConnections()
        }
        builtChannels.append(ChannelEntry(client: client, task: task))
      }
    } catch {
      for entry in builtChannels {
        entry.client.beginGracefulShutdown()
        entry.task.cancel()
      }
      throw error
    }
    self.channels = builtChannels
  }

  deinit {
    for entry in self.channels {
      entry.client.beginGracefulShutdown()
      entry.task.cancel()
    }
  }

  package func shutdown() async {
    if self.shutdownState.exchange(true, ordering: .acquiringAndReleasing) {
      return
    }
    for entry in self.channels {
      entry.client.beginGracefulShutdown()
    }
    for entry in self.channels {
      _ = try? await entry.task.value
    }
  }

  private func nextClient() -> GRPCClient<HTTP2ClientTransport.Posix> {
    let previous = self.nextIndex.wrappingAdd(1, ordering: .relaxed).oldValue
    let index = Int(previous % UInt64(self.channels.count))
    return self.channels[index].client
  }

  package func client(at index: Int) -> GRPCClient<HTTP2ClientTransport.Posix> {
    let normalized = ((index % self.channels.count) + self.channels.count) % self.channels.count
    return self.channels[normalized].client
  }

  package func buildMetadata(
    requestOptions: RequestOptions,
    routingParams: [String],
    extraHeaders: [(name: String, value: String)] = []
  ) async throws -> Metadata {
    let authHeaders: AuthHeaders
    do {
      try await self.credentials.validateUniverseDomain(self.universeDomain)
      authHeaders = try await self.credentials.headers()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw RequestError.io(error)
    }

    var metadata = Metadata()
    let customHeaders = _sanitizeCustomHeaders(requestOptions.headers, excluding: authHeaders)
    for (name, value) in customHeaders {
      metadata.addString(value, forKey: name.lowercased())
    }

    let effectiveQuotaProject = requestOptions.quotaProject ?? self.quotaProject
    for (name, value) in authHeaders {
      if effectiveQuotaProject != nil && name.lowercased() == _HeaderNames.userProject {
        continue
      }
      metadata.addString(value, forKey: name.lowercased())
    }
    if let effectiveQuotaProject {
      metadata.replaceOrAddString(effectiveQuotaProject, forKey: _HeaderNames.userProject)
    }

    metadata.replaceOrAddString(self.apiClientHeaderValue, forKey: _HeaderNames.apiClient)
    if !routingParams.isEmpty {
      metadata.replaceOrAddString(
        routingParams.joined(separator: "&"),
        forKey: _HeaderNames.requestParams
      )
    }
    for (name, value) in extraHeaders {
      metadata.replaceOrAddString(value, forKey: name.lowercased())
    }
    return metadata
  }

  package func unary<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
    descriptor: MethodDescriptor,
    request: Req,
    options: RequestOptions,
    routingParams: [String],
    extraHeaders: [(name: String, value: String)] = [],
    compression: CompressionAlgorithm? = nil,
    subchannelIndex: Int? = nil
  ) async throws -> Resp {
    var callOptions = CallOptions.defaults
    callOptions.maxRequestMessageBytes = Self.defaultMaxMessageBytes
    callOptions.maxResponseMessageBytes = Self.defaultMaxMessageBytes
    callOptions.compression = compression
    if let timeout = options.attemptTimeout ?? self.defaultAttemptTimeout {
      callOptions.timeout = timeout
    }

    let metadata = try await self.buildMetadata(
      requestOptions: options,
      routingParams: routingParams,
      extraHeaders: extraHeaders
    )
    let clientRequest = ClientRequest(message: request, metadata: metadata)
    let targetClient = subchannelIndex.map { self.client(at: $0) } ?? self.nextClient()

    do {
      return try await targetClient.unary(
        request: clientRequest,
        descriptor: descriptor,
        serializer: ProtobufSerializer<Req>(),
        deserializer: ProtobufDeserializer<Resp>(),
        options: callOptions,
        onResponse: { response in
          switch response.accepted {
          case .failure(let rpcError):
            throw Self.convertRPCError(rpcError)
          case .success(let contents):
            switch contents.message {
            case .failure(let rpcError):
              throw Self.convertRPCError(rpcError)
            case .success(let message):
              return message
            }
          }
        }
      )
    } catch let error as RequestError {
      throw error
    } catch let error as RPCError {
      throw Self.convertRPCError(error)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as RuntimeError {
      throw Self.convertRuntimeError(error)
    } catch {
      throw RequestError.io(error)
    }
  }

  package func bidirectionalStreaming<
    Req: SwiftProtobuf.Message,
    Resp: SwiftProtobuf.Message,
    ReturnValue: Sendable
  >(
    descriptor: MethodDescriptor,
    subchannelIndex: Int,
    options: RequestOptions,
    routingParams: [String],
    extraHeaders: [(name: String, value: String)] = [],
    compression: CompressionAlgorithm? = nil,
    producer: @escaping @Sendable (RPCWriter<Req>) async throws -> Void,
    onResponse:
      @escaping @Sendable (
        _ response: StreamingClientResponse<Resp>
      ) async throws -> ReturnValue
  ) async throws -> ReturnValue {
    var callOptions = CallOptions.defaults
    callOptions.maxRequestMessageBytes = Self.defaultMaxMessageBytes
    callOptions.maxResponseMessageBytes = Self.defaultMaxMessageBytes
    callOptions.compression = compression
    if let timeout = options.attemptTimeout {
      callOptions.timeout = timeout
    }

    let metadata = try await self.buildMetadata(
      requestOptions: options,
      routingParams: routingParams,
      extraHeaders: extraHeaders
    )
    let streamingRequest = StreamingClientRequest(metadata: metadata, producer: producer)
    let targetClient = self.client(at: subchannelIndex)

    do {
      return try await targetClient.bidirectionalStreaming(
        request: streamingRequest,
        descriptor: descriptor,
        serializer: ProtobufSerializer<Req>(),
        deserializer: ProtobufDeserializer<Resp>(),
        options: callOptions,
        onResponse: onResponse
      )
    } catch let error as RequestError {
      throw error
    } catch let error as RPCError {
      throw Self.convertRPCError(error)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as RuntimeError {
      throw Self.convertRuntimeError(error)
    } catch {
      throw RequestError.io(error)
    }
  }

  package static func isEmptyRequestOptions(_ options: GoogleGax.RequestOptions) -> Bool {
    options.attemptTimeout == nil
      && options.idempotent == nil
      && options.retryPolicy == nil
      && options.backoffPolicy == nil
      && options.retryThrottler == nil
      && options.quotaProject == nil
      && options.headers.isEmpty
  }

  package static func mergeRequestOptions(
    base: GoogleGax.RequestOptions,
    override: GoogleGax.RequestOptions
  ) -> GoogleGax.RequestOptions {
    var merged = base
    if let attemptTimeout = override.attemptTimeout {
      merged.attemptTimeout = attemptTimeout
    }
    if let idempotent = override.idempotent {
      merged.idempotent = idempotent
    }
    if let retryPolicy = override.retryPolicy {
      merged.retryPolicy = retryPolicy
    }
    if let backoffPolicy = override.backoffPolicy {
      merged.backoffPolicy = backoffPolicy
    }
    if let retryThrottler = override.retryThrottler {
      merged.retryThrottler = retryThrottler
    }
    if let quotaProject = override.quotaProject {
      merged.quotaProject = quotaProject
    }
    if !override.headers.isEmpty {
      var combined = base.headers.filter { existing in
        !override.headers.contains(name: existing.name)
      }
      combined.append(contentsOf: override.headers.map { ($0.name, $0.value) })
      merged.headers = GoogleGax.HTTPHeaders(combined)
    }
    return merged
  }

  package static func convertRuntimeError(_ error: RuntimeError) -> RequestError {
    .io(error)
  }

  package static func convertRPCError(_ rpcError: RPCError) -> RequestError {
    if rpcError.cause != nil {
      return .io(rpcError)
    }
    if let contentType = rpcError.metadata[stringValues: "content-type"].first(where: { _ in true }
    ),
      !contentType.starts(with: "application/grpc")
    {
      return .io(rpcError)
    }
    if let googleStatus = try? rpcError.unpackGoogleRPCStatus() {
      let code = GoogleRpc.Code(intValue: googleStatus.code.rawValue)
      let message = googleStatus.message.isEmpty ? rpcError.message : googleStatus.message
      let details = googleStatus.details.map { Self.convertErrorDetail($0) }
      return .service(ServiceError(code: code, message: message, details: details))
    }
    let code = GoogleRpc.Code(intValue: rpcError.code.rawValue)
    return .service(ServiceError(code: code, message: rpcError.message, details: []))
  }

  private static func convertErrorDetail(_ detail: ErrorDetails) -> StatusDetail {
    if let info = detail.errorInfo {
      var item = GoogleRpc.ErrorInfo()
      item.reason = info.reason
      item.domain = info.domain
      item.metadata = info.metadata
      return .errorInfo(item)
    } else if let badRequest = detail.badRequest {
      var item = GoogleRpc.BadRequest()
      item.fieldViolations = badRequest.violations.map { v in
        var violation = GoogleRpc.BadRequest.FieldViolation()
        violation.field = v.field
        violation.description = v.violationDescription
        violation.reason = v.reason
        if let lm = v.localizedMessage {
          var localized = GoogleRpc.LocalizedMessage()
          localized.locale = lm.locale
          localized.message = lm.message
          violation.localizedMessage = localized
        }
        return violation
      }
      return .badRequest(item)
    } else if let debugInfo = detail.debugInfo {
      var item = GoogleRpc.DebugInfo()
      item.stackEntries = debugInfo.stack
      item.detail = debugInfo.detail
      return .debugInfo(item)
    } else if let help = detail.help {
      var item = GoogleRpc.Help()
      item.links = help.links.map { l in
        var link = GoogleRpc.Help.Link()
        link.description = l.linkDescription
        link.url = l.url
        return link
      }
      return .help(item)
    } else if let localizedMessage = detail.localizedMessage {
      var item = GoogleRpc.LocalizedMessage()
      item.locale = localizedMessage.locale
      item.message = localizedMessage.message
      return .localizedMessage(item)
    } else if let preconditionFailure = detail.preconditionFailure {
      var item = GoogleRpc.PreconditionFailure()
      item.violations = preconditionFailure.violations.map { v in
        var violation = GoogleRpc.PreconditionFailure.Violation()
        violation.type = v.type
        violation.subject = v.subject
        violation.description = v.violationDescription
        return violation
      }
      return .preconditionFailure(item)
    } else if let quotaFailure = detail.quotaFailure {
      var item = GoogleRpc.QuotaFailure()
      item.violations = quotaFailure.violations.map { v in
        var violation = GoogleRpc.QuotaFailure.Violation()
        violation.subject = v.subject
        violation.description = v.violationDescription
        violation.apiService = v.apiService
        violation.quotaMetric = v.quotaMetric
        violation.quotaId = v.quotaID
        violation.quotaDimensions = v.quotaDimensions
        violation.quotaValue = Int64(v.quotaValue)
        violation.futureQuotaValue = v.futureQuotaValue.map(Int64.init)
        return violation
      }
      return .quotaFailure(item)
    } else if let requestInfo = detail.requestInfo {
      var item = GoogleRpc.RequestInfo()
      item.requestId = requestInfo.requestID
      item.servingData = requestInfo.servingData
      return .requestInfo(item)
    } else if let resourceInfo = detail.resourceInfo {
      var item = GoogleRpc.ResourceInfo()
      item.resourceType = resourceInfo.type
      item.resourceName = resourceInfo.name
      item.owner = resourceInfo.owner
      item.description = resourceInfo.errorDescription
      return .resourceInfo(item)
    } else if let retryInfo = detail.retryInfo {
      var item = GoogleRpc.RetryInfo()
      let seconds = retryInfo.delay.components.seconds
      let nanos = Int32(retryInfo.delay.components.attoseconds / 1_000_000_000)
      item.retryDelay = try? GoogleWKT.WKTDuration(seconds: seconds, nanos: nanos)
      return .retryInfo(item)
    } else if let protoAny = detail.any, let wktAny = try? GoogleWKT.WKTAny(proto: protoAny) {
      return .other(wktAny)
    } else {
      do {
        return .other(try GoogleWKT.WKTAny(fromMessage: GoogleWKT.WKTEmpty()))
      } catch {
        fatalError("Failed to construct fallback GoogleWKT.WKTAny: \(error)")
      }
    }
  }
}
