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

// [START pubsub_quickstart_subscriber]
public func quickstartSubscriber(
  projectID: String,
  subscriptionID: String,
  clientOptions: GoogleGax.ClientOptions = .init()
) async throws -> Int {
  let subscriberClient = try SubscriberClient(
    SubscriberClientOptions().with {
      $0.client = clientOptions
      $0.projectID = projectID
    }
  )
  let stream = try subscriberClient.subscribe(subscription: subscriptionID)
  var receivedCount = 0
  for try await received in stream {
    let body = String(decoding: received.message.data, as: UTF8.self)
    print("Received message \(received.message.messageID): \(body)")
    received.ack()
    receivedCount += 1
    break
  }
  _ = try await stream.stop()
  return receivedCount
}
// [END pubsub_quickstart_subscriber]

// [START pubsub_subscriber_async_pull]
public func subscribeAsyncPull(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String,
  maxMessages: Int = 10
) async throws -> [String] {
  let stream = try subscriber.subscribe(subscription: subscription)
  var receivedIDs: [String] = []
  for try await received in stream {
    print("Received message \(received.message.messageID)")
    received.ack()
    receivedIDs.append(received.message.messageID)
    if receivedIDs.count >= maxMessages {
      break
    }
  }
  _ = try await stream.stop()
  return receivedIDs
}
// [END pubsub_subscriber_async_pull]

// [START pubsub_subscriber_async_pull_custom_attributes]
public func subscribeWithCustomAttributes(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> [[String: String]] {
  let stream = try subscriber.subscribe(subscription: subscription)
  var attributeMaps: [[String: String]] = []
  for try await received in stream {
    print(
      "Message \(received.message.messageID) attributes: \(received.message.attributes)"
    )
    attributeMaps.append(received.message.attributes)
    received.ack()
    break
  }
  _ = try await stream.stop()
  return attributeMaps
}
// [END pubsub_subscriber_async_pull_custom_attributes]

// [START pubsub_subscriber_concurrency_control]
public func subscribeWithConcurrencyControl(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String,
  maxConcurrentHandlers: Int = 4
) async throws -> Int {
  let options = SubscribeOptions().with {
    $0.streamCount = 2
    $0.maxOutstandingMessages = 500
    $0.enablePerStreamFlowControl = true
  }
  let stream = try subscriber.subscribe(subscription: subscription, options: options)
  let processed = try await withThrowingTaskGroup(of: Void.self) { group in
    var count = 0
    for try await received in stream {
      if count >= maxConcurrentHandlers {
        try await group.next()
      }
      group.addTask {
        let body = String(decoding: received.message.data, as: UTF8.self)
        print("Processed concurrently: \(body)")
        received.ack()
      }
      count += 1
    }
    try await group.waitForAll()
    return count
  }
  _ = try await stream.stop()
  return processed
}
// [END pubsub_subscriber_concurrency_control]

// [START pubsub_subscriber_error_listener]
public func subscribeWithErrorListener(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async -> (delivered: Int, terminalError: (any Error)?) {
  var delivered = 0
  do {
    let stream = try subscriber.subscribe(subscription: subscription)
    do {
      for try await received in stream {
        delivered += 1
        received.ack()
      }
      _ = try await stream.stop()
      return (delivered, nil)
    } catch {
      print("StreamingPull terminated with error: \(error)")
      _ = try? await stream.stop(
        options: SubscriberShutdownOptions().with {
          $0.behavior = .nackImmediately
        }
      )
      return (delivered, error)
    }
  } catch {
    print("Subscribe configuration error: \(error)")
    return (0, error)
  }
}
// [END pubsub_subscriber_error_listener]

// [START pubsub_subscriber_exactly_once]
public func subscribeExactlyOnce(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> [SettlementStatus] {
  let stream = try subscriber.subscribe(subscription: subscription)
  var statuses: [SettlementStatus] = []
  for try await received in stream {
    do {
      let ackResult = try await received.ackWithResult()
      print("Confirmed settlement status: \(ackResult.status)")
      statuses.append(ackResult.status)
    } catch PubSubError.settlementFailed(let ackError) {
      print("Settlement rejected: \(ackError.status) - \(ackError.message)")
      statuses.append(ackError.status)
    }
    break
  }
  _ = try await stream.stop()
  return statuses
}
// [END pubsub_subscriber_exactly_once]

// [START pubsub_dead_letter_delivery_attempt]
public func subscribeDeadLetterDeliveryAttempt(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> [Int?] {
  let stream = try subscriber.subscribe(subscription: subscription)
  var attempts: [Int?] = []
  for try await received in stream {
    print(
      "Message \(received.message.messageID) deliveryAttempt: \(String(describing: received.message.deliveryAttempt))"
    )
    attempts.append(received.message.deliveryAttempt)
    received.ack()
    break
  }
  _ = try await stream.stop()
  return attempts
}
// [END pubsub_dead_letter_delivery_attempt]

// [START pubsub_optimistic_subscribe]
public func optimisticSubscribe(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> Int {
  // Connects directly to StreamingPull without a pre-flight GetSubscription RPC.
  let stream = try subscriber.subscribe(subscription: subscription)
  var count = 0
  for try await received in stream {
    count += 1
    received.ack()
    break
  }
  _ = try await stream.stop()
  return count
}
// [END pubsub_optimistic_subscribe]

// [START pubsub_subscriber_flow_settings]
public func subscribeWithFlowSettings(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> Int {
  let options = SubscribeOptions().with {
    $0.streamCount = 2
    $0.maxOutstandingMessages = 200
    $0.maxOutstandingBytes = 10 * 1024 * 1024
    $0.enablePerStreamFlowControl = true
    $0.maxExtension = .seconds(1_800)
  }
  let stream = try subscriber.subscribe(subscription: subscription, options: options)
  var count = 0
  for try await received in stream {
    count += 1
    received.ack()
    break
  }
  _ = try await stream.stop()
  return count
}
// [END pubsub_subscriber_flow_settings]
