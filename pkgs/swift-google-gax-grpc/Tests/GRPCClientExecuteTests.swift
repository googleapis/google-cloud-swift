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
import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleGaxGRPC
import GoogleRpc
import SwiftProtobuf
import Testing

@Suite struct GRPCClientExecuteTests {
  // A simple test service implementing mock gRPC methods.
  private struct EchoService: RegistrableRPCService {
    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
      router.registerHandler(
        forMethod: MethodDescriptor(
          service: ServiceDescriptor(package: "test", service: "Echo"),
          method: "Echo"
        ),
        deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
        serializer: ProtobufSerializer<Google_Protobuf_Empty>()
      ) { _, _ in
        StreamingServerResponse(metadata: [:]) { writer in
          try await writer.write(Google_Protobuf_Empty())
          return [:]
        }
      }

      router.registerHandler(
        forMethod: MethodDescriptor(
          service: ServiceDescriptor(package: "test", service: "Echo"),
          method: "FailWithDetails"
        ),
        deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
        serializer: ProtobufSerializer<Google_Protobuf_Empty>()
      ) { _, _ in
        let status = GoogleRPCStatus(
          code: .notFound,
          message: "The requested bucket does not exist",
          details: [
            .errorInfo(
              reason: "RESOURCE_NOT_FOUND",
              domain: "googleapis.com"
            )
          ]
        )

        var metadata = Metadata()
        metadata.replaceOrAddBinary(
          try status.serializedBytes(),
          forKey: "grpc-status-details-bin"
        )
        metadata.replaceOrAddString("application/grpc", forKey: "content-type")

        throw RPCError(
          code: .notFound,
          message: "The requested bucket does not exist",
          metadata: metadata
        )
      }

      router.registerHandler(
        forMethod: MethodDescriptor(
          service: ServiceDescriptor(package: "test", service: "Echo"),
          method: "FailWithoutDetails"
        ),
        deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
        serializer: ProtobufSerializer<Google_Protobuf_Empty>()
      ) { _, _ in
        var metadata = Metadata()
        metadata.replaceOrAddString("application/grpc", forKey: "content-type")

        throw RPCError(
          code: .unauthenticated,
          message: "Missing authentication token",
          metadata: metadata
        )
      }
    }
  }

  @Test func executeSuccess() async throws {
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 0),
        transportSecurity: .plaintext
      ),
      services: [EchoService()]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      let listeningAddress = try await server.listeningAddress?.ipv4
      guard let port = listeningAddress?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      var clientOptions = ClientOptions()
      clientOptions.endpoint = endpoint
      clientOptions.credentials = try Credentials(configuration: .anonymous)

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions(),
        clientHeader: ""
      )
    }
  }

  @Test func executeRpcErrorWithStatusDetails() async throws {
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 0),
        transportSecurity: .plaintext
      ),
      services: [EchoService()]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      let listeningAddress = try await server.listeningAddress?.ipv4
      guard let port = listeningAddress?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      var clientOptions = ClientOptions()
      clientOptions.endpoint = endpoint
      clientOptions.credentials = try Credentials(configuration: .anonymous)

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      do {
        let _: Google_Protobuf_Empty = try await client.execute(
          path: "/test.Echo/FailWithDetails",
          request: Google_Protobuf_Empty(),
          options: RequestOptions(),
          clientHeader: ""
        )
        Issue.record("Expected execute to throw RequestError")
      } catch let requestError as RequestError {
        guard case let .service(serviceError) = requestError else {
          Issue.record("Expected .service error, got \(requestError)")
          return
        }
        #expect(serviceError.code == .notFound)
        #expect(serviceError.message == "The requested bucket does not exist")
        #expect(serviceError.details.count == 1)
        guard case let .errorInfo(info) = serviceError.details[0] else {
          Issue.record("Expected .errorInfo detail, got \(serviceError.details[0])")
          return
        }
        #expect(info.reason == "RESOURCE_NOT_FOUND")
        #expect(info.domain == "googleapis.com")
      } catch {
        Issue.record("Expected RequestError, got \(error)")
      }
    }
  }

  @Test func executeRpcErrorWithoutStatusDetails() async throws {
    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 0),
        transportSecurity: .plaintext
      ),
      services: [EchoService()]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      let listeningAddress = try await server.listeningAddress?.ipv4
      guard let port = listeningAddress?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      var clientOptions = ClientOptions()
      clientOptions.endpoint = endpoint
      clientOptions.credentials = try Credentials(configuration: .anonymous)

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      do {
        let _: Google_Protobuf_Empty = try await client.execute(
          path: "/test.Echo/FailWithoutDetails",
          request: Google_Protobuf_Empty(),
          options: RequestOptions(),
          clientHeader: ""
        )
        Issue.record("Expected execute to throw RequestError")
      } catch let requestError as RequestError {
        guard case let .service(serviceError) = requestError else {
          Issue.record("Expected .service error, got \(requestError)")
          return
        }
        #expect(serviceError.code == .unauthenticated)
        #expect(serviceError.message == "Missing authentication token")
        #expect(serviceError.details.isEmpty)
      } catch {
        Issue.record("Expected RequestError, got \(error)")
      }
    }
  }

  @Test func executeConnectionFailure() async throws {
    // Attempting to connect to an unopened port on localhost with plaintext
    let endpoint = "http://127.0.0.1:1"
    var clientOptions = ClientOptions()
    clientOptions.endpoint = endpoint
    clientOptions.credentials = try Credentials(configuration: .anonymous)

    let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
    defer {
      client.close()
    }

    do {
      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions(),
        clientHeader: ""
      )
      Issue.record("Expected execute to fail")
    } catch let requestError as RequestError {
      // Must be mapped to .io error
      guard case .io = requestError else {
        Issue.record("Expected .io error for connection failure, got \(requestError)")
        return
      }
    } catch {
      Issue.record("Expected RequestError, got \(error)")
    }
  }

  @Test(arguments: [
    // Uses ClientOptions.quotaProject when RequestOptions.quotaProject is nil
    (clientQuota: "client-quota-proj", requestQuota: nil as String?, expected: "client-quota-proj"),
    // RequestOptions.quotaProject overrides ClientOptions.quotaProject
    (
      clientQuota: "client-quota-proj",
      requestQuota: "request-quota-proj",
      expected: "request-quota-proj"
    ),
  ])
  func executeQuotaProjectPrecedence(
    clientQuota: String?,
    requestQuota: String?,
    expected: String
  ) async throws {
    actor MetadataCollector {
      var userProjects: [String] = []
      func record(_ values: [String]) {
        userProjects = values
      }
    }
    let collector = MetadataCollector()

    struct InspectingEchoService: RegistrableRPCService {
      let collector: MetadataCollector
      func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
          forMethod: MethodDescriptor(
            service: ServiceDescriptor(package: "test", service: "Echo"),
            method: "Echo"
          ),
          deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
          serializer: ProtobufSerializer<Google_Protobuf_Empty>()
        ) { request, _ in
          let values = request.metadata[stringValues: _HeaderNames.userProject].map { String($0) }
          await collector.record(values)
          return StreamingServerResponse(metadata: [:]) { writer in
            try await writer.write(Google_Protobuf_Empty())
            return [:]
          }
        }
      }
    }

    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 0),
        transportSecurity: .plaintext
      ),
      services: [InspectingEchoService(collector: collector)]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      let listeningAddress = try await server.listeningAddress?.ipv4
      guard let port = listeningAddress?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      var clientOptions = ClientOptions()
      clientOptions.endpoint = endpoint
      clientOptions.credentials = try Credentials(configuration: .anonymous)
      clientOptions.quotaProject = clientQuota

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let requestOptions = RequestOptions().with { $0.quotaProject = requestQuota }
      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: requestOptions,
        clientHeader: ""
      )
      #expect(await collector.userProjects == [expected])
    }
  }

  @Test func executeRequestOptionsHeaders() async throws {
    actor MetadataCollector {
      var idempotencyTokens: [String] = []
      var customHeaders: [String] = []
      var multiHeaders: [String] = []
      var authorizations: [String] = []
      var apiKeys: [String] = []
      var userProjects: [String] = []
      var apiClients: [String] = []
      var requestParams: [String] = []

      func record(
        token: [String], custom: [String], multi: [String], auth: [String], key: [String],
        userProject: [String], apiClient: [String], params: [String]
      ) {
        idempotencyTokens = token
        customHeaders = custom
        multiHeaders = multi
        authorizations = auth
        apiKeys = key
        userProjects = userProject
        apiClients = apiClient
        requestParams = params
      }
    }
    let collector = MetadataCollector()

    struct InspectingEchoService: RegistrableRPCService {
      let collector: MetadataCollector
      func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
          forMethod: MethodDescriptor(
            service: ServiceDescriptor(package: "test", service: "Echo"),
            method: "Echo"
          ),
          deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
          serializer: ProtobufSerializer<Google_Protobuf_Empty>()
        ) { request, _ in
          let tokenValues = request.metadata[stringValues: "x-goog-gcs-idempotency-token"].map {
            String($0)
          }
          let customValues = request.metadata[stringValues: "x-custom-header"].map { String($0) }
          let multiValues = request.metadata[stringValues: "x-multi-header"].map { String($0) }
          let authValues = request.metadata[stringValues: "authorization"].map { String($0) }
          let keyValues = request.metadata[stringValues: "x-goog-api-key"].map { String($0) }
          let projectValues = request.metadata[stringValues: "x-goog-user-project"].map {
            String($0)
          }
          let clientValues = request.metadata[stringValues: "x-goog-api-client"].map { String($0) }
          let paramValues = request.metadata[stringValues: "x-goog-request-params"].map {
            String($0)
          }
          await collector.record(
            token: tokenValues,
            custom: customValues,
            multi: multiValues,
            auth: authValues,
            key: keyValues,
            userProject: projectValues,
            apiClient: clientValues,
            params: paramValues
          )
          return StreamingServerResponse(metadata: [:]) { writer in
            try await writer.write(Google_Protobuf_Empty())
            return [:]
          }
        }
      }
    }

    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv4(host: "127.0.0.1", port: 0),
        transportSecurity: .plaintext
      ),
      services: [InspectingEchoService(collector: collector)]
    )

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        try await server.serve()
      }

      let listeningAddress = try await server.listeningAddress?.ipv4
      guard let port = listeningAddress?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      var clientOptions = ClientOptions()
      clientOptions.endpoint = endpoint
      clientOptions.credentials = try Credentials(configuration: .anonymous)

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let requestOptions = RequestOptions().with {
        $0.headers = [
          ("x-multi-header", "first"),
          ("x-multi-header", "second"),
        ]
        $0.headers["x-goog-gcs-idempotency-token"] = "token-12345"
        $0.headers["X-Custom-Header"] = "overridden-val"
        $0.headers["x-custom-header"] = "custom-val"
        $0.headers["authorization"] = "Bearer bad-token"
        $0.headers["x-goog-api-key"] = "bad-key"
        $0.headers["x-goog-user-project"] = "bad-project"
        $0.headers["x-goog-api-client"] = "bad-client"
        $0.headers["x-goog-request-params"] = "bad-params"
      }
      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: requestOptions,
        clientHeader: "test-client-header",
        routingParams: ["foo=bar"]
      )
      #expect(await collector.idempotencyTokens == ["token-12345"])
      #expect(await collector.customHeaders == ["custom-val"])
      #expect(await collector.multiHeaders == ["first", "second"])
      #expect(await collector.authorizations.isEmpty)
      #expect(await collector.apiKeys.isEmpty)
      #expect(await collector.userProjects.isEmpty)
      #expect(await collector.apiClients == ["test-client-header"])
      #expect(await collector.requestParams == ["foo=bar"])
    }
  }
}
