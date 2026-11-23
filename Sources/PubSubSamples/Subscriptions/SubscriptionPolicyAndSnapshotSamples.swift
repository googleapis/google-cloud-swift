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

import GoogleCloudPubSubV1
import GoogleWKT

// [START pubsub_dead_letter_create_subscription]
public func createDeadLetterSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  deadLetterTopicID: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.deadLetterPolicy = DeadLetterPolicy().with { dlp in
        dlp.deadLetterTopic = "projects/\(projectID)/topics/\(deadLetterTopicID)"
        dlp.maxDeliveryAttempts = 5
      }
    }
  )
  print("Created dead-letter subscription: \(sub.name)")
  return sub
}
// [END pubsub_dead_letter_create_subscription]

// [START pubsub_dead_letter_update_subscription]
public func updateDeadLetterSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  deadLetterTopicID: String
) async throws -> Subscription {
  let sub = try await client.updateSubscription(
    request: UpdateSubscriptionRequest().with {
      $0.subscription = Subscription().with { sub in
        sub.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
        sub.topic = "projects/\(projectID)/topics/\(topicID)"
        sub.deadLetterPolicy = DeadLetterPolicy().with { dlp in
          dlp.deadLetterTopic = "projects/\(projectID)/topics/\(deadLetterTopicID)"
          dlp.maxDeliveryAttempts = 10
        }
      }
      $0.updateMask = GoogleWKT.WKTFieldMask().with { mask in
        mask.paths = ["dead_letter_policy"]
      }
    }
  )
  print("Updated dead-letter policy: \(sub.name)")
  return sub
}
// [END pubsub_dead_letter_update_subscription]

// [START pubsub_dead_letter_remove]
public func removeDeadLetterPolicy(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String
) async throws -> Subscription {
  let sub = try await client.updateSubscription(
    request: UpdateSubscriptionRequest().with {
      $0.subscription = Subscription().with { sub in
        sub.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
        sub.topic = "projects/\(projectID)/topics/\(topicID)"
      }
      $0.updateMask = GoogleWKT.WKTFieldMask().with { mask in
        mask.paths = ["dead_letter_policy"]
      }
    }
  )
  print("Removed dead-letter policy: \(sub.name)")
  return sub
}
// [END pubsub_dead_letter_remove]

// [START pubsub_create_subscription_with_exactly_once_delivery]
public func createSubscriptionWithExactlyOnceDelivery(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.enableExactlyOnceDelivery = true
    }
  )
  print("Created EOD subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_subscription_with_exactly_once_delivery]

// [START pubsub_create_subscription_with_filter]
public func createSubscriptionWithFilter(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  filter: String = "attributes.author = \"gcp\""
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.filter = filter
    }
  )
  print("Created filtered subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_subscription_with_filter]

// [START pubsub_enable_subscription_ordering]
public func enableSubscriptionOrdering(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.enableMessageOrdering = true
    }
  )
  print("Created ordered subscription: \(sub.name)")
  return sub
}
// [END pubsub_enable_subscription_ordering]

// [START pubsub_create_snapshot]
public func createSnapshot(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String,
  snapshotID: String
) async throws -> Snapshot {
  let snapshot = try await client.createSnapshot(
    request: CreateSnapshotRequest().with {
      $0.name = "projects/\(projectID)/snapshots/\(snapshotID)"
      $0.subscription = "projects/\(projectID)/subscriptions/\(subscriptionID)"
    }
  )
  print("Created snapshot: \(snapshot.name)")
  return snapshot
}
// [END pubsub_create_snapshot]

// [START pubsub_list_snapshots]
public func listSnapshots(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String
) async throws -> [String] {
  var names: [String] = []
  let items = client.listSnapshotsByItems(
    request: ListSnapshotsRequest().with {
      $0.project = "projects/\(projectID)"
    }
  )
  for try await snap in items {
    print("Snapshot: \(snap.name)")
    names.append(snap.name)
  }
  return names
}
// [END pubsub_list_snapshots]

// [START pubsub_delete_snapshot]
public func deleteSnapshot(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  snapshotID: String
) async throws {
  try await client.deleteSnapshot(
    snapshot: "projects/\(projectID)/snapshots/\(snapshotID)"
  )
  print("Deleted snapshot \(snapshotID)")
}
// [END pubsub_delete_snapshot]

// [START pubsub_seek_time]
public func seekToTimestamp(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String,
  time: GoogleWKT.WKTTimestamp
) async throws {
  _ = try await client.seek(
    request: SeekRequest().with {
      $0.subscription = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.target = .time(time)
    }
  )
  print("Seeked subscription \(subscriptionID) to timestamp \(time)")
}
// [END pubsub_seek_time]

// [START pubsub_seek_snapshot]
public func seekToSnapshot(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String,
  snapshotID: String
) async throws {
  _ = try await client.seek(
    request: SeekRequest().with {
      $0.subscription = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.target = .snapshot("projects/\(projectID)/snapshots/\(snapshotID)")
    }
  )
  print("Seeked subscription \(subscriptionID) to snapshot \(snapshotID)")
}
// [END pubsub_seek_snapshot]
