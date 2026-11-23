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

// [START pubsub_create_pull_subscription]
public func createPullSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.ackDeadlineSeconds = 10
    }
  )
  print("Created pull subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_pull_subscription]

// [START pubsub_create_push_subscription]
public func createPushSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  pushEndpoint: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.ackDeadlineSeconds = 10
      $0.pushConfig = PushConfig().with { push in
        push.pushEndpoint = pushEndpoint
      }
    }
  )
  print("Created push subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_push_subscription]

// [START pubsub_create_unwrapped_push_subscription]
public func createUnwrappedPushSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  pushEndpoint: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.ackDeadlineSeconds = 10
      $0.pushConfig = PushConfig().with { push in
        push.pushEndpoint = pushEndpoint
        push.wrapper = .noWrapper(
          PushConfig.NoWrapper().with { noWrapper in
            noWrapper.writeMetadata = true
          }
        )
      }
    }
  )
  print("Created unwrapped push subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_unwrapped_push_subscription]

// [START pubsub_update_push_configuration]
public func updatePushConfig(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String,
  pushEndpoint: String
) async throws {
  try await client.modifyPushConfig(
    request: ModifyPushConfigRequest().with {
      $0.subscription = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.pushConfig = PushConfig().with { push in
        push.pushEndpoint = pushEndpoint
      }
    }
  )
  print("Updated push configuration for \(subscriptionID)")
}
// [END pubsub_update_push_configuration]

// [START pubsub_create_bigquery_subscription]
public func createBigQuerySubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  bigqueryTableID: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.bigqueryConfig = BigQueryConfig().with { bq in
        bq.table = bigqueryTableID
        bq.writeMetadata = true
      }
    }
  )
  print("Created BigQuery subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_bigquery_subscription]

// [START pubsub_create_cloud_storage_subscription]
public func createCloudStorageSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  topicID: String,
  subscriptionID: String,
  bucketName: String
) async throws -> Subscription {
  let sub = try await client.createSubscription(
    request: Subscription().with {
      $0.name = "projects/\(projectID)/subscriptions/\(subscriptionID)"
      $0.topic = "projects/\(projectID)/topics/\(topicID)"
      $0.cloudStorageConfig = CloudStorageConfig().with { gcs in
        gcs.bucket = bucketName
        gcs.filenamePrefix = "pubsub-"
        gcs.filenameSuffix = ".txt"
        gcs.maxDuration = try? GoogleWKT.WKTDuration(seconds: 300, nanos: 0)
        gcs.maxBytes = 10_000_000
      }
    }
  )
  print("Created Cloud Storage subscription: \(sub.name)")
  return sub
}
// [END pubsub_create_cloud_storage_subscription]

// [START pubsub_list_subscriptions]
public func listSubscriptions(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String
) async throws -> [String] {
  var names: [String] = []
  let items = client.listSubscriptionsByItems(
    request: ListSubscriptionsRequest().with {
      $0.project = "projects/\(projectID)"
    }
  )
  for try await sub in items {
    print("Subscription: \(sub.name)")
    names.append(sub.name)
  }
  return names
}
// [END pubsub_list_subscriptions]

// [START pubsub_delete_subscription]
public func deleteSubscription(
  client: any Clients.SubscriptionAdminProtocol,
  projectID: String,
  subscriptionID: String
) async throws {
  try await client.deleteSubscription(
    subscription: "projects/\(projectID)/subscriptions/\(subscriptionID)"
  )
  print("Deleted subscription \(subscriptionID)")
}
// [END pubsub_delete_subscription]
