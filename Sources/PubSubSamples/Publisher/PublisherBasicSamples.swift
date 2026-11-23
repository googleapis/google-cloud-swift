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
import GoogleCloudPubSub
import GoogleGax

// [START pubsub_quickstart_publisher]
public func quickstartPublisher(
  projectID: String,
  topicID: String,
  clientOptions: GoogleGax.ClientOptions = .init()
) async throws -> PublishResult {
  let publisherClient = try PublisherClient(
    PublisherClientOptions().with {
      $0.client = clientOptions
      $0.projectID = projectID
    }
  )
  let publisher = try publisherClient.publisher(topic: topicID)
  let message = Message(data: Data("Hello, Cloud Pub/Sub!".utf8))
  let result = try await publisher.publish(message)
  print("Published quickstart message ID: \(result.messageID)")
  _ = try await publisherClient.shutdown()
  return result
}
// [END pubsub_quickstart_publisher]

// [START pubsub_publish]
public func publishMessages(
  publisher: any Clients.PublisherProtocol,
  payloads: [String]
) async throws -> [String] {
  var handles: [PublishHandle] = []
  handles.reserveCapacity(payloads.count)
  for text in payloads {
    let message = Message(data: Data(text.utf8))
    handles.append(try await publisher.startPublish(message))
  }
  var messageIDs: [String] = []
  messageIDs.reserveCapacity(handles.count)
  for handle in handles {
    let result = try await handle.result()
    print("Published message ID: \(result.messageID)")
    messageIDs.append(result.messageID)
  }
  return messageIDs
}
// [END pubsub_publish]

// [START pubsub_publish_custom_attributes]
public func publishWithCustomAttributes(
  publisher: any Clients.PublisherProtocol
) async throws -> PublishResult {
  let message = Message(
    data: Data("Message with custom attributes".utf8),
    attributes: ["origin": "swift-sample", "username": "gcp"]
  )
  let result = try await publisher.publish(message)
  print("Published message with attributes: \(result.messageID)")
  return result
}
// [END pubsub_publish_custom_attributes]

// [START pubsub_publish_with_error_handler]
public func publishWithErrorHandler(
  publisher: any Clients.PublisherProtocol,
  payload: String
) async -> PublishResult? {
  do {
    let result = try await publisher.publish(Message(data: Data(payload.utf8)))
    print("Published message ID: \(result.messageID)")
    return result
  } catch let error as PubSubError {
    print("Client publish error: \(error)")
  } catch let error as GoogleGax.RequestError {
    print("RPC publish error: \(error)")
  } catch {
    print("Unexpected publish error: \(error)")
  }
  return nil
}
// [END pubsub_publish_with_error_handler]

// [START pubsub_publisher_batch_settings]
public func publishWithBatchSettings(
  publisherClient: any Clients.PublisherClientProtocol,
  topic: String,
  messages: [String]
) async throws -> [String] {
  let topicOptions = TopicPublisherOptions().with {
    $0.batching = BatchingOptions().with { batching in
      batching.countThreshold = 100
      batching.byteThreshold = 1_024
      batching.delayThreshold = .milliseconds(10)
    }
  }
  let publisher = try publisherClient.publisher(topic: topic, options: topicOptions)
  var handles: [PublishHandle] = []
  for text in messages {
    handles.append(try await publisher.startPublish(Message(data: Data(text.utf8))))
  }
  _ = try await publisher.flush()
  var ids: [String] = []
  for handle in handles {
    ids.append(try await handle.result().messageID)
  }
  _ = try await publisher.shutdown()
  return ids
}
// [END pubsub_publisher_batch_settings]

// [START pubsub_publish_with_ordering_keys]
public func publishWithOrderingKeys(
  publisher: any Clients.PublisherProtocol
) async throws -> [String] {
  var handles: [PublishHandle] = []
  for (text, key) in [("msg1", "key1"), ("msg2", "key1"), ("msg3", "key2")] {
    let message = Message(data: Data(text.utf8), orderingKey: key)
    handles.append(try await publisher.startPublish(message))
  }
  var messageIDs: [String] = []
  for handle in handles {
    let result = try await handle.result()
    print("Published ordered message: \(result.messageID)")
    messageIDs.append(result.messageID)
  }
  return messageIDs
}
// [END pubsub_publish_with_ordering_keys]

// [START pubsub_resume_publish_with_ordering_keys]
public func resumePublishWithOrderingKeys(
  publisher: any Clients.PublisherProtocol,
  orderingKey: String,
  payload: String
) async throws -> PublishResult {
  let message = Message(data: Data(payload.utf8), orderingKey: orderingKey)
  do {
    return try await publisher.publish(message)
  } catch PubSubError.orderingKeyPaused {
    _ = try await publisher.resumePublishing(orderingKey: orderingKey)
    return try await publisher.publish(message)
  }
}
// [END pubsub_resume_publish_with_ordering_keys]
