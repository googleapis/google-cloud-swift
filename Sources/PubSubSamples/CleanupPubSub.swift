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

/// Tracks Pub/Sub admin resource names created during live sample execution for cleanup.
public struct PubSubSampleCleanupBag: Sendable {
  public var subscriptions: [String] = []
  public var snapshots: [String] = []
  public var topics: [String] = []
  public var schemas: [String] = []

  public init() {}
}

/// Deletes temporary subscriptions, snapshots, topics, and schemas created during a sample run.
public func cleanupPubSubSampleResources(
  topicAdmin: any Clients.TopicAdminProtocol,
  subscriptionAdmin: any Clients.SubscriptionAdminProtocol,
  schemaClient: any Clients.SchemaServiceProtocol,
  bag: PubSubSampleCleanupBag
) async {
  for sub in bag.subscriptions.reversed() {
    do {
      try await subscriptionAdmin.deleteSubscription(subscription: sub)
    } catch {
      print("Cleanup warning: failed to delete subscription \(sub): \(error)")
    }
  }
  for snapshot in bag.snapshots.reversed() {
    do {
      try await subscriptionAdmin.deleteSnapshot(snapshot: snapshot)
    } catch {
      print("Cleanup warning: failed to delete snapshot \(snapshot): \(error)")
    }
  }
  for topic in bag.topics.reversed() {
    do {
      try await topicAdmin.deleteTopic(topic: topic)
    } catch {
      print("Cleanup warning: failed to delete topic \(topic): \(error)")
    }
  }
  for schema in bag.schemas.reversed() {
    do {
      try await schemaClient.deleteSchema(name: schema)
    } catch {
      print("Cleanup warning: failed to delete schema \(schema): \(error)")
    }
  }
}
