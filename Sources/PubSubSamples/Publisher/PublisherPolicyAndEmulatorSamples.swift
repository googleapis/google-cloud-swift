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
import GoogleGax

// [START pubsub_publisher_retry_settings]
public func publishWithRetrySettings(
  publisherClient: any Clients.PublisherClientProtocol,
  topic: String,
  payload: String
) async throws -> PublishResult {
  let options = TopicPublisherOptions().with {
    $0.request = GoogleGax.RequestOptions().with { req in
      req.retryPolicy = PubSubRetryPolicy().with { retry in
        retry.timeLimit = .seconds(600)
        retry.maxAttempts = 5
      }
      req.backoffPolicy = ExponentialBackoff(
        clamping: .milliseconds(100),
        maximumDelay: .seconds(60),
        scaling: 1.3
      )
    }
  }
  let publisher = try publisherClient.publisher(topic: topic, options: options)
  let result = try await publisher.publish(Message(data: Data(payload.utf8)))
  _ = try await publisher.shutdown()
  return result
}
// [END pubsub_publisher_retry_settings]

// [START pubsub_publisher_concurrency_control]
public func publishWithConcurrencyControl(
  projectID: String,
  topicID: String,
  payloads: [String],
  clientOptions: GoogleGax.ClientOptions = .init()
) async throws -> [String] {
  let publisherClient = try PublisherClient(
    PublisherClientOptions().with {
      $0.client = clientOptions
      $0.projectID = projectID
      $0.subchannelCount = 4
    }
  )
  let publisher = try publisherClient.publisher(topic: topicID)
  var handles: [PublishHandle] = []
  handles.reserveCapacity(payloads.count)
  for text in payloads {
    handles.append(try await publisher.startPublish(Message(data: Data(text.utf8))))
  }
  var ids: [String] = []
  for handle in handles {
    ids.append(try await handle.result().messageID)
  }
  _ = try await publisherClient.shutdown()
  return ids
}
// [END pubsub_publisher_concurrency_control]

// [START pubsub_publisher_flow_control]
public func publishWithFlowControl(
  publisherClient: any Clients.PublisherClientProtocol,
  topic: String,
  payloads: [String]
) async throws -> [String] {
  let options = TopicPublisherOptions().with {
    $0.flowControl = PublisherFlowControlOptions().with { fc in
      fc.maxPendingMessages = 1_000
      fc.maxPendingBytes = 10 * 1024 * 1024
      fc.limitExceededBehavior = .block
    }
  }
  let publisher = try publisherClient.publisher(topic: topic, options: options)
  var handles: [PublishHandle] = []
  for text in payloads {
    handles.append(try await publisher.startPublish(Message(data: Data(text.utf8))))
  }
  var ids: [String] = []
  for handle in handles {
    ids.append(try await handle.result().messageID)
  }
  _ = try await publisher.shutdown()
  return ids
}
// [END pubsub_publisher_flow_control]

// [START pubsub_publisher_with_compression]
public func publishWithCompression(
  publisherClient: any Clients.PublisherClientProtocol,
  topic: String
) async throws -> PublishResult {
  let options = TopicPublisherOptions().with {
    $0.compression = CompressionOptions().with { comp in
      comp.isEnabled = true
      comp.bytesThreshold = 240
    }
  }
  let publisher = try publisherClient.publisher(topic: topic, options: options)
  let message = Message(data: Data(repeating: UInt8(ascii: "A"), count: 1_024))
  let result = try await publisher.publish(message)
  _ = try await publisher.shutdown()
  return result
}
// [END pubsub_publisher_with_compression]

// [START pubsub_publish_hedging_settings]
public func publishWithHedgingSettings(
  publisherClient: any Clients.PublisherClientProtocol,
  topic: String,
  payload: String
) async throws -> PublishResult {
  let options = TopicPublisherOptions().with {
    $0.hedging = HedgingOptions().with { hedging in
      hedging.isEnabled = true
      hedging.delay = .seconds(1)
      hedging.maxTokens = 50
      hedging.refillRatio = 0.1
    }
  }
  let publisher = try publisherClient.publisher(topic: topic, options: options)
  let result = try await publisher.publish(Message(data: Data(payload.utf8)))
  _ = try await publisher.shutdown()
  return result
}
// [END pubsub_publish_hedging_settings]

// [START pubsub_use_emulator]
public func usePubSubEmulator(
  projectID: String,
  topicID: String,
  subscriptionID: String,
  emulatorHost: String = "localhost:8085"
) async throws {
  // PublisherClient and SubscriberClient also automatically honor the
  // PUBSUB_EMULATOR_HOST environment variable when ClientOptions.endpoint is nil.
  let clientOptions = try GoogleGax.ClientOptions().with {
    $0.endpoint = "http://\(emulatorHost)"
    $0.credentials = try Credentials(configuration: .anonymous)
  }
  let publisherClient = try PublisherClient(
    PublisherClientOptions().with {
      $0.client = clientOptions
      $0.projectID = projectID
    }
  )
  let publisher = try publisherClient.publisher(topic: topicID)
  let published = try await publisher.publish(Message(data: Data("emulator-msg".utf8)))
  print("Published via emulator: \(published.messageID)")

  let subscriberClient = try SubscriberClient(
    SubscriberClientOptions().with {
      $0.client = clientOptions
      $0.projectID = projectID
    }
  )
  let stream = try subscriberClient.subscribe(subscription: subscriptionID)
  for try await received in stream {
    print("Received via emulator: \(received.message.messageID)")
    received.ack()
    break
  }
  _ = try await stream.stop()
  _ = try await publisherClient.shutdown()
}
// [END pubsub_use_emulator]
