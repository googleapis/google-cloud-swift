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
import PubSubConformanceProtos
import PubSubConformanceProxyCore
import Testing

@Suite struct PubSubConformanceProxyTests {
  @Test func getCapabilitiesReportsExpectedSwiftFlagsAndDefaults() async throws {
    let service = PubSubProxyService()
    let transport = HTTP2ServerTransport.Posix(
      address: .ipv4(host: "127.0.0.1", port: 0),
      transportSecurity: .plaintext
    )
    let server = GRPCServer(transport: transport, services: [service])
    let serveTask = Task { try await server.serve() }
    defer {
      server.beginGracefulShutdown()
      serveTask.cancel()
    }

    let addr = try #require(try await transport.listeningAddress.ipv4)
    let clientTransport = try HTTP2ClientTransport.Posix(
      target: .ipv4(address: "127.0.0.1", port: addr.port),
      transportSecurity: .plaintext
    )
    let client = GRPCClient(transport: clientTransport)
    let connTask = Task { try await client.runConnections() }
    defer {
      client.beginGracefulShutdown()
      connTask.cancel()
    }

    let response = try await client.unary(
      request: ClientRequest(message: Pubsub_Conformance_V1_GetCapabilitiesRequest()),
      descriptor: MethodDescriptor(
        fullyQualifiedService: "pubsub.conformance.v1.PubSubProxy",
        method: "GetCapabilities"
      ),
      serializer: ProtobufSerializer<Pubsub_Conformance_V1_GetCapabilitiesRequest>(),
      deserializer: ProtobufDeserializer<Pubsub_Conformance_V1_GetCapabilitiesResponse>(),
      options: .defaults
    ) { res in
      try res.message
    }

    #expect(response.clientLanguage == "swift")
    #expect(response.clientLibrary == "GoogleCloudPubSub")
    #expect(response.supportsMonitoring == false)
    #expect(response.supportsUnaryPull == true)
    #expect(response.supportsEodReceiptModack == true)
    #expect(response.supportsOrderingOptIn == false)
    #expect(response.supportsSubscriberOrdering == false)
    #expect(response.defaults.publishBatchCountThreshold == 100)
    #expect(response.defaults.subscriberDefaultStreamAckDeadlineSeconds == 60)
    #expect(response.defaults.retryInitialDelayMs == 100)
  }
}
