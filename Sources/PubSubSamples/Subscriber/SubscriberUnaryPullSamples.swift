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

import GoogleCloudPubSub

// [START pubsub_subscriber_sync_pull]
public func subscriberSyncPull(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String,
  maxMessages: Int = 10
) async throws -> [String] {
  let options = PullOptions().with {
    $0.maxMessages = maxMessages
    $0.returnImmediately = true
  }
  let result = try await subscriber.pull(subscription: subscription, options: options)
  var pulledIDs: [String] = []
  for received in result.messages {
    print("Pulled message \(received.message.messageID)")
    pulledIDs.append(received.message.messageID)
    received.ack()
  }
  return pulledIDs
}
// [END pubsub_subscriber_sync_pull]

// [START pubsub_subscriber_sync_pull_with_lease]
public func subscriberSyncPullWithLease(
  subscriber: any Clients.SubscriberProtocol,
  subscription: String
) async throws -> [SettlementStatus] {
  let options = PullOptions().with {
    $0.maxMessages = 5
    $0.maxExtension = .seconds(3_600)
    $0.minAckExtension = .seconds(10)
    $0.maxAckExtension = .seconds(600)
    $0.enableAdaptiveAckExtension = true
  }
  let result = try await subscriber.pull(subscription: subscription, options: options)
  var statuses: [SettlementStatus] = []
  for received in result.messages {
    // Leases renew automatically in the background while processing.
    let ackResult = try await received.ackWithResult()
    statuses.append(ackResult.status)
  }
  return statuses
}
// [END pubsub_subscriber_sync_pull_with_lease]
