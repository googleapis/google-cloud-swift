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
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import GoogleCloudAuth
@_spi(GoogleCloudInternal) import GoogleCloudGax
import SwiftProtobuf

/// Implements a generic gRPC client for the Swift SDK client libraries.
///
/// ## Usage and Lifecycle Guidelines
/// - **Resource Management**: Each `_GRPCClient` manages an underlying HTTP/2 transport connection
///   loop running inside a background `Task`.
/// - **Shutdown**:
///   - Calling ``close()`` initiates a graceful shutdown (`beginGracefulShutdown()`). In-flight RPCs
///     are allowed to finish executing, while any new RPCs will be rejected.
///   - If ``close()`` is not explicitly called, the background connection task is automatically shut down
///     when the `_GRPCClient` instance is deallocated (`deinit`).
/// - **Async Invariants & Lifetimes**:
///   - Calls to ``execute(path:request:options:clientHeader:routingParams:)`` retain the `_GRPCClient`
///     instance for the duration of the asynchronous execution, so the instance will not be deallocated
///     while an RPC is in flight.
///   - Calling ``close()`` will allow active in-flight RPCs to drain, but any subsequent calls to
///     ``execute`` will fail.
@_spi(GoogleCloudInternal)
public final class _GRPCClient: Sendable {
  let client: GRPCClient<HTTP2ClientTransport.Posix>
  let connectionTask: Task<Void, any Error>
  let credentials: GoogleCloudAuth.Credentials

  public init(from options: ClientOptions, withDefaultEndpoint defaultEndpoint: String) throws {
    self.credentials = try options.credentials ?? GoogleCloudAuth.Credentials()

    let rawEndpoint = options.endpoint ?? defaultEndpoint
    let endpointWithScheme = rawEndpoint.contains("://") ? rawEndpoint : "https://\(rawEndpoint)"
    guard let components = URLComponents(string: endpointWithScheme),
      let host = components.host, !host.isEmpty
    else {
      throw ClientError.invalidEndpoint(rawEndpoint)
    }

    let isSecure = components.scheme == "https"
    let port = components.port ?? (isSecure ? 443 : 80)
    let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity =
      isSecure ? .tls : .plaintext

    let transport = try HTTP2ClientTransport.Posix(
      target: .dns(host: host, port: port),
      transportSecurity: transportSecurity
    )

    let client = GRPCClient(transport: transport)
    self.client = client
    self.connectionTask = Task {
      try await client.runConnections()
    }
  }

  /// Initiates graceful shutdown of the client connection.
  ///
  /// In-flight RPCs are allowed to finish, but no new requests will be accepted.
  public func close() {
    self.client.beginGracefulShutdown()
  }

  deinit {
    self.client.beginGracefulShutdown()
    self.connectionTask.cancel()
  }

  /// Executes a generic unary gRPC request.
  ///
  /// - Parameters:
  ///   - path: The gRPC method path (e.g. `"/google.storage.control.v2.StorageControl/CreateFolder"`).
  ///   - request: The protobuf request message.
  ///   - options: Request-level options (such as attempt timeout).
  ///   - clientHeader: The `x-goog-api-client` header value.
  ///   - routingParams: A list of `key=value` routing parameters (per AIP-4222) to send in the `x-goog-request-params` header. The parameters must already be percent-encoded by the caller.
  /// - Returns: The protobuf response message.
  public func execute<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
    path: String,
    request: Req,
    options: RequestOptions,
    clientHeader: String,
    routingParams: [String] = []
  ) async throws -> Resp {
    var callOptions = CallOptions.defaults
    if let attemptTimeout = options.attemptTimeout {
      callOptions.timeout = attemptTimeout
    }

    var metadata = Metadata()
    let authHeaders = try await self.credentials.headers()
    for (key, value) in authHeaders {
      metadata.addString(value, forKey: key)
    }

    metadata.addString(clientHeader, forKey: GoogleCloudGax._HeaderNames.apiClient)
    if !routingParams.isEmpty {
      metadata.addString(
        routingParams.joined(separator: "&"),
        forKey: _HeaderNames.requestParams
      )
    }

    let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let parts = normalizedPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2 else {
      throw ClientError.invalidEndpoint("Invalid gRPC path: \(path)")
    }
    let service = String(parts[0])
    let method = String(parts[1])

    let descriptor = MethodDescriptor(
      service: ServiceDescriptor(fullyQualifiedService: service),
      method: method
    )

    let clientRequest = ClientRequest(message: request, metadata: metadata)
    do {
      return try await self.client.unary(
        request: clientRequest,
        descriptor: descriptor,
        serializer: ProtobufSerializer<Req>(),
        deserializer: ProtobufDeserializer<Resp>(),
        options: callOptions,
        onResponse: Self.handleResponse
      )
    } catch let error as RequestError {
      throw error
    } catch let error as RPCError {
      throw error.toRequestError()
    } catch {
      throw RequestError.io(error)
    }
  }

  private static func handleResponse<Resp>(
    _ response: ClientResponse<Resp>
  ) throws -> Resp {
    switch response.accepted {
    case .failure(let rpcError):
      throw rpcError.toRequestError()
    case .success(let contents):
      switch contents.message {
      case .failure(let rpcError):
        throw rpcError.toRequestError()
      case .success(let message):
        return message
      }
    }
  }
}
