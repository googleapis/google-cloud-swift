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
@_spi(GoogleCloudInternal) import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleGaxGRPC
import GoogleRpc
import SwiftProtobuf
import Synchronization
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
        options: RequestOptions()
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
          options: RequestOptions()
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
          options: RequestOptions()
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
        options: RequestOptions()
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
        options: requestOptions
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
        routingParams: ["foo=bar"]
      )
      #expect(await collector.idempotencyTokens == ["token-12345"])
      #expect(await collector.customHeaders == ["custom-val"])
      #expect(await collector.multiHeaders == ["first", "second"])
      #expect(await collector.authorizations.isEmpty)
      #expect(await collector.apiKeys.isEmpty)
      #expect(await collector.userProjects.isEmpty)
      #expect(await collector.apiClients == [client.clientHeader.build()])
      #expect(await collector.requestParams == ["foo=bar"])
    }
  }

  @Test func executeDefaultClientHeader() async throws {
    actor MetadataCollector {
      var apiClients: [String] = []
      func record(_ values: [String]) {
        apiClients = values
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
          let values = request.metadata[stringValues: GoogleGax._HeaderNames.apiClient].map {
            String($0)
          }
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

      let client = try _GRPCClient(from: clientOptions, withDefaultEndpoint: endpoint)
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
      let recorded = await collector.apiClients
      #expect(recorded.count == 1)
      if let header = recorded.first {
        #expect(header.contains("gl-swift/"))
        #expect(header.contains("gax/"))
        #expect(header.contains("grpc/"))
        #expect(header.contains("pb/"))
        #expect(!header.contains("rest/"))
      }
    }
  }

  @Test func executeClientHeaderConfiguredAtInit() async throws {
    actor MetadataCollector {
      var apiClients: [String] = []
      func record(_ values: [String]) {
        apiClients = values
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
          let values = request.metadata[stringValues: GoogleGax._HeaderNames.apiClient].map {
            String($0)
          }
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

      let client = try _GRPCClient(
        from: clientOptions,
        withDefaultEndpoint: endpoint,
        clientHeader: .gapic(packageVersion: "2.3.4")
      )
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
      let recorded = await collector.apiClients
      #expect(recorded.count == 1)
      if let header = recorded.first {
        #expect(header.contains("gapic/2.3.4"))
        #expect(header.contains("gl-swift/"))
        #expect(header.contains("gax/"))
        #expect(header.contains("grpc/"))
        #expect(header.contains("pb/"))
        #expect(!header.contains("rest/"))
      }
    }
  }

  @Test(arguments: [
    (
      optionUniverse: "my-custom-universe.com" as String?,
      environment: [:] as [String: String],
      expectedUniverse: "my-custom-universe.com"
    ),
    (
      optionUniverse: nil,
      environment: ["GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com"],
      expectedUniverse: "env.universe.com"
    ),
  ])
  func executeUniverseDomainMismatch(
    optionUniverse: String?,
    environment: [String: String],
    expectedUniverse: String
  ) async throws {
    let endpoint = "http://127.0.0.1:1"
    var options = ClientOptions()
    options.endpoint = endpoint
    options.universeDomain = optionUniverse
    options.credentials = try Credentials(
      configuration: .apiKey("test-api-key"),
      environment: [:]
    )

    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: endpoint,
      environment: environment
    )
    defer { client.close() }

    let error = await #expect(throws: RequestError.self) {
      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
    }
    guard case let .io(underlying) = error else {
      Issue.record("Expected RequestError.io, got \(String(describing: error))")
      return
    }
    #expect(underlying is CredentialsError)
    #expect(String(describing: underlying).contains(expectedUniverse))
    #expect(String(describing: underlying).contains("googleapis.com"))
  }

  @Test func defaultCredentialsForwardsEnvironmentAndCatchesFileMismatch() async throws {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".json"
    )
    defer { try? FileManager.default.removeItem(at: tempFile) }
    try Data(
      """
      {
        "type": "authorized_user",
        "client_id": "id",
        "client_secret": "secret",
        "refresh_token": "refresh",
        "universe_domain": "googleapis.com"
      }
      """.utf8
    ).write(to: tempFile)

    var options = ClientOptions()
    options.endpoint = "http://127.0.0.1:1"
    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      environment: [
        "GOOGLE_APPLICATION_CREDENTIALS": tempFile.path,
        "GOOGLE_CLOUD_UNIVERSE_DOMAIN": "env.universe.com",
      ]
    )
    defer { client.close() }

    let error = await #expect(throws: RequestError.self) {
      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
    }
    guard case let .io(underlying) = error else {
      Issue.record("Expected RequestError.io, got \(String(describing: error))")
      return
    }
    #expect(underlying is CredentialsError)
  }

  @Test(arguments: [
    (
      universeDomain: "googleapis.com",
      credentials: CredentialsConfiguration.apiKey("test-api-key")
    ),
    (
      universeDomain: "my-custom-universe.com",
      credentials: .anonymous
    ),
  ])
  func executeUniverseDomainSuccess(
    universeDomain: String,
    credentials: CredentialsConfiguration
  ) async throws {
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
      var options = ClientOptions()
      options.endpoint = endpoint
      options.universeDomain = universeDomain
      options.credentials = try Credentials(configuration: credentials, environment: [:])

      let client = try _GRPCClient(
        from: options,
        withDefaultEndpoint: endpoint,
        environment: [:]
      )
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
    }
  }

  @Test func executeMultipleAndEmptyRoutingParams() async throws {
    actor RequestParamsCollector {
      var recorded: [[String]] = []
      func record(_ values: [String]) {
        recorded.append(values)
      }
    }
    let collector = RequestParamsCollector()

    struct InspectingEchoService: RegistrableRPCService {
      let collector: RequestParamsCollector
      func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
          forMethod: MethodDescriptor(
            service: ServiceDescriptor(package: "test", service: "Echo"),
            method: "Echo"
          ),
          deserializer: ProtobufDeserializer<Google_Protobuf_Empty>(),
          serializer: ProtobufSerializer<Google_Protobuf_Empty>()
        ) { request, _ in
          let paramValues = request.metadata[stringValues: "x-goog-request-params"].map {
            String($0)
          }
          await collector.record(paramValues)
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

      let testCases: [(routingParams: [String], expectedHeader: [String])] = [
        (
          _RoutingMatcher.format([
            ("name", _RoutingMatcher.value("billingAccounts/012345", matching: [.multiWildcard])),
            (
              "destination_parent",
              _RoutingMatcher.value("organizations/67890", matching: [.multiWildcard])
            ),
          ]),
          ["name=billingAccounts%2F012345&destination_parent=organizations%2F67890"]
        ),
        (
          _RoutingMatcher.format([
            ("primary_empty", _RoutingMatcher.value("", matching: [.multiWildcard])),
            ("parent", _RoutingMatcher.value("organizations/67890", matching: [.multiWildcard])),
          ]),
          ["parent=organizations%2F67890"]
        ),
        (
          _RoutingMatcher.format([
            ("primary_empty", _RoutingMatcher.value("", matching: [.multiWildcard])),
            ("parent", _RoutingMatcher.value(nil, matching: [.multiWildcard])),
          ]),
          []
        ),
      ]
      for testCase in testCases {
        let _: Google_Protobuf_Empty = try await client.execute(
          path: "/test.Echo/Echo",
          request: Google_Protobuf_Empty(),
          options: RequestOptions(),
          routingParams: testCase.routingParams
        )
      }
      #expect(await collector.recorded == testCases.map(\.expectedHeader))
    }
  }

  private static func runIPv6EchoIfAvailable(bindHost: String) async throws {
    final class ServerStateBox: Sendable {
      struct State: Sendable {
        var didBind = false
        var serveError: (any Error)?
      }
      let state = Mutex(State())
    }

    let server = GRPCServer(
      transport: .http2NIOPosix(
        address: .ipv6(host: bindHost, port: 0),
        transportSecurity: .plaintext
      ),
      services: [EchoService()]
    )
    let box = ServerStateBox()

    try await withThrowingDiscardingTaskGroup { group in
      group.addTask {
        do {
          try await server.serve()
        } catch {
          box.state.withLock { $0.serveError = error }
        }
      }

      let listeningAddress: SocketAddress.IPv6?
      do {
        listeningAddress = try await server.listeningAddress?.ipv6
      } catch {
        // Skip gracefully in container/CI environments (such as GCB Docker) where IPv6 loopback
        // is disabled, without letting `server.serve()`'s bind error fail the task group.
        server.beginGracefulShutdown()
        return
      }
      guard let port = listeningAddress?.port else {
        server.beginGracefulShutdown()
        return
      }
      box.state.withLock { $0.didBind = true }

      var options = ClientOptions()
      options.endpoint = "http://[\(bindHost)]:\(port)"
      options.credentials = try Credentials(configuration: .anonymous)

      let client = try _GRPCClient(
        from: options,
        withDefaultEndpoint: "https://example.googleapis.com",
        environment: [:]
      )
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      #expect(client.endpoint.host == bindHost)
      #expect(client.endpoint.authority == "[\(bindHost)]:\(port)")

      let _: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: RequestOptions()
      )
    }

    let finalState = box.state.withLock { $0 }
    if finalState.didBind, let serveError = finalState.serveError {
      throw serveError
    }
  }

  @Test func executeIPv6LoopbackEndpoint() async throws {
    var staticOptions = ClientOptions()
    staticOptions.endpoint = "http://[::1]:8080"
    staticOptions.credentials = try Credentials(configuration: .anonymous)
    let staticClient = try _GRPCClient(
      from: staticOptions,
      withDefaultEndpoint: "https://example.googleapis.com",
      environment: [:]
    )
    staticClient.close()
    #expect(staticClient.endpoint.host == "::1")
    #expect(staticClient.endpoint.authority == "[::1]:8080")

    // Verify unbindable IPv6 addresses (matching Docker containers with IPv6 disabled) skip cleanly.
    try await Self.runIPv6EchoIfAvailable(bindHost: "2001:db8::1")
    // Execute live loopback RPC when IPv6 loopback is enabled on the host.
    try await Self.runIPv6EchoIfAvailable(bindHost: "::1")
  }

  @Test func executePermanentCredentialsErrorNotRetriedByRetryLoop() async throws {
    let endpoint = "http://127.0.0.1:1"
    var options = ClientOptions()
    options.endpoint = endpoint
    options.universeDomain = "custom-universe.com"
    options.credentials = try Credentials(
      configuration: .apiKey("test-api-key"),
      environment: [:]
    )
    options.retryThrottler = CircuitBreaker()

    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: endpoint,
      environment: [:]
    )
    defer { client.close() }

    let retryLoop = _RetryLoop(options: RequestOptions(), withDefault: options, idempotent: true)
    var attempts = 0
    let error = await #expect(throws: RequestError.self) {
      let _: Google_Protobuf_Empty = try await retryLoop.run(
        inner: { _ in
          attempts += 1
          return try await client.execute(
            path: "/test.Echo/Echo",
            request: Google_Protobuf_Empty(),
            options: RequestOptions()
          )
        },
        sleep: { _ in
          Issue.record("RetryLoop must not sleep on permanent CredentialsError")
        }
      )
    }
    #expect(attempts == 1)
    if case let .io(underlying)? = error {
      #expect(underlying is CredentialsError)
    } else {
      Issue.record("Expected RequestError.io(CredentialsError), got \(String(describing: error))")
    }
  }

  @Test func executeTransientCredentialsErrorRetriedByRetryLoop() async throws {
    struct TransientSubjectProvider: SubjectTokenProvider {
      func subjectToken() async throws -> String {
        throw URLError(.networkConnectionLost)
      }
    }
    final class FlakyAccessTokenProvider: AccessTokenProvider, Sendable {
      let transientError: CredentialsError
      private let calls = Mutex(0)

      init(transientError: CredentialsError) {
        self.transientError = transientError
      }

      var callCount: Int {
        calls.withLock { $0 }
      }

      func accessToken() async throws -> AccessToken {
        let current = calls.withLock { count -> Int in
          count += 1
          return count
        }
        if current == 1 {
          throw transientError
        }
        return AccessToken(token: "recovered-grpc-token")
      }
    }

    let extConfig = ExternalAccountConfig(
      credentialSource: .programmatic(subjectTokenProvider: TransientSubjectProvider()),
      audience:
        "//iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p/providers/pr",
      subjectTokenType: .idToken,
      tokenURL: URL(string: "https://sts.googleapis.com/v1/token")!
    )
    let extCreds = try Credentials(configuration: .externalAccount(extConfig), environment: [:])
    let transientError: CredentialsError
    do {
      _ = try await extCreds.headers()
      Issue.record("Expected transient CredentialsError")
      return
    } catch let err as CredentialsError {
      transientError = err
    }

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

      guard let port = try await server.listeningAddress?.ipv4?.port else {
        Issue.record("Failed to get listening port")
        server.beginGracefulShutdown()
        return
      }

      let endpoint = "http://127.0.0.1:\(port)"
      let flakyProvider = FlakyAccessTokenProvider(transientError: transientError)
      var options = ClientOptions()
      options.endpoint = endpoint
      options.credentials = try Credentials(
        configuration: .accessToken(AccessTokenConfig(provider: flakyProvider)),
        environment: [:]
      )
      options.retryThrottler = CircuitBreaker()

      let client = try _GRPCClient(
        from: options,
        withDefaultEndpoint: endpoint,
        environment: [:]
      )
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let retryLoop = _RetryLoop(options: RequestOptions(), withDefault: options, idempotent: true)
      var attempts = 0
      var sleepCalls = 0
      let _: Google_Protobuf_Empty = try await retryLoop.run(
        inner: { _ in
          attempts += 1
          return try await client.execute(
            path: "/test.Echo/Echo",
            request: Google_Protobuf_Empty(),
            options: RequestOptions()
          )
        },
        sleep: { _ in
          sleepCalls += 1
        }
      )
      #expect(attempts == 2)
      #expect(sleepCalls == 1)
      #expect(flakyProvider.callCount == 2)
    }
  }
}
