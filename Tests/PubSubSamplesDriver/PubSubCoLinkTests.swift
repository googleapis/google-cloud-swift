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
import GoogleAuth
import GoogleCloudPubSub
import GoogleCloudPubSubV1
import GoogleCloudTestHelpers
import GoogleGax
import Testing

@Suite struct PubSubCoLinkTests {
  @Test func adminAndVeneerCoImportWithZeroAmbiguity() throws {
    // Unqualified references proving zero symbol collision between GoogleCloudPubSub and GoogleCloudPubSubV1.
    let topic = Topic().with {
      $0.name = "projects/p/topics/t"
    }
    let subscription = Subscription().with {
      $0.name = "projects/p/subscriptions/s"
      $0.topic = topic.name
    }
    let schema = Schema().with {
      $0.name = "projects/p/schemas/sc"
      $0.type = .avro
      $0.definition = "{}"
    }
    let outbound = Message(data: Data("co-import".utf8), attributes: ["source": "admin-data"])
    let inbound = ReceivedMessage(
      message: outbound,
      isExactlyOnce: true,
      ackHandler: UnimplementedAckHandler()
    )
    let ackResult = AckResult(status: .success)
    let publishResult = PublishResult(messageID: "msg-co-import")

    #expect(topic.name == "projects/p/topics/t")
    #expect(subscription.topic == topic.name)
    #expect(schema.type == .avro)
    #expect(inbound.message.attributes["source"] == "admin-data")
    #expect(inbound.isExactlyOnce)
    #expect(ackResult.status == .success)
    #expect(publishResult.messageID == "msg-co-import")
  }

  @Test func adminAndDataPlaneClientsInstantiateAndExecuteTogether() async throws {
    let captureServer = try await CaptureServer(
      responding: Data(#"{"name":"projects/co-proj/topics/co-topic"}"#.utf8)
    )
    defer { Task { try? await captureServer.shutdown() } }

    let adminOptions = try ClientOptions().with {
      $0.endpoint = captureServer.endpoint
      $0.credentials = try Credentials(configuration: .anonymous)
    }
    let topicAdmin = try TopicAdminClient(adminOptions)
    let subscriptionAdmin = try SubscriptionAdminClient(adminOptions)
    let schemaClient = try SchemaServiceClient(adminOptions)

    let dataOptions = try ClientOptions().with {
      $0.endpoint = captureServer.endpoint
      $0.credentials = try Credentials(configuration: .anonymous)
    }
    let publisherClient = try PublisherClient(
      PublisherClientOptions().with {
        $0.client = dataOptions
        $0.projectID = "co-proj"
      }
    )
    let blockingPublisher = try BlockingPublisherClient(
      BlockingPublisherClientOptions().with {
        $0.client = dataOptions
        $0.projectID = "co-proj"
      }
    )
    let subscriberClient = try SubscriberClient(
      SubscriberClientOptions().with {
        $0.client = dataOptions
        $0.projectID = "co-proj"
      }
    )

    let createdTopic = try await topicAdmin.createTopic(
      request: Topic().with { $0.name = "projects/co-proj/topics/co-topic" }
    )
    #expect(createdTopic.name == "projects/co-proj/topics/co-topic")
    #expect(captureServer.requests.count == 1)

    let publisher = try publisherClient.publisher(topic: "co-topic")
    let stream = try subscriberClient.subscribe(subscription: "co-sub")
    _ = try? await stream.stop(
      options: SubscriberShutdownOptions().with {
        $0.behavior = .waitForProcessing
        $0.timeout = .zero
      }
    )
    _ = try? await publisher.shutdown()
    _ = try? await publisherClient.shutdown()
    _ = (subscriptionAdmin, schemaClient, blockingPublisher)
  }
}

private struct UnimplementedAckHandler: AckHandlerProtocol {}
