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

import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import GoogleAuth
@_spi(GoogleCloudInternal) import GoogleGax
@_spi(GoogleCloudInternal) @testable import GoogleGaxGRPC
import SwiftProtobuf
import Testing

@Suite struct GRPCClientEmulatorTests {
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
    }
  }

  @Test func ignoresEmulatorEnvVarWhenParameterIsNilOrEmpty() throws {
    let options = ClientOptions().with {
      $0.credentials = try? Credentials(configuration: .anonymous)
    }

    let clientNil = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: nil,
      environment: ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]
    )
    defer { clientNil.close() }
    #expect(clientNil.targetHost == "example.googleapis.com")
    #expect(clientNil.targetPort == 443)

    let clientEmpty = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "",
      environment: ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]
    )
    defer { clientEmpty.close() }
    #expect(clientEmpty.targetHost == "example.googleapis.com")
    #expect(clientEmpty.targetPort == 443)
  }

  @Test func grpcClientUsesEmulatorEndpointAndAnonymousCredentials() async throws {
    let options = ClientOptions()
    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: [
        "EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085",
        "NO_GCE_CHECK": "true",
        "GOOGLE_APPLICATION_CREDENTIALS": "/nonexistent/path/creds.json",
      ]
    )
    defer { client.close() }

    #expect(client.targetHost == "127.0.0.1")
    #expect(client.targetPort == 8085)
    #expect(client.authority == "127.0.0.1:8085")
    let authHeaders = try await client.credentials.headers()
    #expect(authHeaders.isEmpty)
  }

  @Test func grpcClientPreservesExplicitCredentialsWithEmulator() async throws {
    let options = ClientOptions().with {
      $0.credentials = try? Credentials(configuration: .apiKey("custom-test-key"))
    }
    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "localhost:8085"]
    )
    defer { client.close() }

    #expect(client.targetHost == "localhost")
    #expect(client.targetPort == 8085)
    let authHeaders = try await client.credentials.headers()
    #expect(
      authHeaders.contains(where: { $0.name == "x-goog-api-key" && $0.value == "custom-test-key" }))
  }

  @Test func grpcClientExplicitEndpointBeatsEmulator() throws {
    let options = ClientOptions().with {
      $0.endpoint = "https://us-central1-example.googleapis.com"
      $0.credentials = try? Credentials(configuration: .anonymous)
    }
    let client = try _GRPCClient(
      from: options,
      withDefaultEndpoint: "https://example.googleapis.com",
      emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
      environment: ["EXAMPLE_EMULATOR_HOST": "127.0.0.1:8085"]
    )
    defer { client.close() }

    #expect(client.targetHost == "us-central1-example.googleapis.com")
    #expect(client.targetPort == 443)
    #expect(client.authority == "us-central1-example.googleapis.com")
  }

  @Test func grpcClientExecutesOverPlaintextAgainstEmulatorHostPort() async throws {
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

      let client = try _GRPCClient(
        from: ClientOptions(),
        withDefaultEndpoint: "https://example.googleapis.com",
        emulatorEnvironmentVariable: "EXAMPLE_EMULATOR_HOST",
        environment: [
          "EXAMPLE_EMULATOR_HOST": "127.0.0.1:\(port)",
          "NO_GCE_CHECK": "true",
          "GOOGLE_APPLICATION_CREDENTIALS": "/nonexistent/path/creds.json",
        ]
      )
      defer {
        client.close()
        server.beginGracefulShutdown()
      }

      let response: Google_Protobuf_Empty = try await client.execute(
        path: "/test.Echo/Echo",
        request: Google_Protobuf_Empty(),
        options: .init()
      )
      #expect(response == Google_Protobuf_Empty())
    }
  }
}
