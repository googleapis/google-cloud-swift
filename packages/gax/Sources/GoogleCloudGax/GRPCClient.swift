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
import GRPC
import GoogleCloudAuth
import NIO
import SwiftProtobuf

/// Implements a generic gRPC client for the Swift SDK client libraries.
@_spi(GoogleCloudInternal)
public struct _GRPCClient: Sendable {
  public let connection: ClientConnection
  public let credentials: GoogleCloudAuth.Credentials

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
    let group = MultiThreadedEventLoopGroup.singleton
    let builder =
      isSecure
      ? ClientConnection.usingPlatformAppropriateTLS(for: group)
      : ClientConnection.insecure(group: group)

    self.connection = builder.connect(host: host, port: port)
  }

  /// Executes a generic unary gRPC request.
  public func execute<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
    path: String,
    request: Req,
    options: RequestOptions,
    clientHeader: String,
    routingParams: [String] = []
  ) async throws -> Resp {
    var callOptions = CallOptions()

    if let attemptTimeout = options.attemptTimeout {
      callOptions.timeLimit = .timeout(.nanoseconds(Int64(attemptTimeout / .nanoseconds(1))))
    }

    let authHeaders = try await self.credentials.headers()
    for (key, value) in authHeaders {
      callOptions.customMetadata.add(name: key, value: value)
    }

    callOptions.customMetadata.add(name: "x-goog-api-client", value: clientHeader)
    if !routingParams.isEmpty {
      callOptions.customMetadata.add(
        name: "x-goog-request-params",
        value: routingParams.joined(separator: "&")
      )
    }

    let call: UnaryCall<Req, Resp> = self.connection.makeUnaryCall(
      path: path,
      request: request,
      callOptions: callOptions
    )
    return try await call.response.get()
  }
}
