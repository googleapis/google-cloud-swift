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

// [START pubsub_quickstart_create_topic]
public func quickstartCreateTopic(
  projectID: String,
  topicID: String,
  client: (any Clients.TopicAdminProtocol)? = nil
) async throws -> Topic {
  let admin: any Clients.TopicAdminProtocol = try client ?? TopicAdminClient()
  let topic = try await admin.createTopic(
    request: Topic().with {
      $0.name = "projects/\(projectID)/topics/\(topicID)"
    }
  )
  print("Created topic: \(topic.name)")
  return topic
}
// [END pubsub_quickstart_create_topic]

// [START pubsub_create_topic]
public func createTopic(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String
) async throws -> Topic {
  let topic = try await client.createTopic(
    request: Topic().with {
      $0.name = "projects/\(projectID)/topics/\(topicID)"
    }
  )
  print("Created topic: \(topic.name)")
  return topic
}
// [END pubsub_create_topic]

// [START pubsub_list_topics]
public func listTopics(
  client: any Clients.TopicAdminProtocol,
  projectID: String
) async throws -> [String] {
  var names: [String] = []
  let items = client.listTopicsByItems(
    request: ListTopicsRequest().with {
      $0.project = "projects/\(projectID)"
    }
  )
  for try await topic in items {
    print("Topic: \(topic.name)")
    names.append(topic.name)
  }
  return names
}
// [END pubsub_list_topics]

// [START pubsub_list_topic_subscriptions]
public func listTopicSubscriptions(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String
) async throws -> [String] {
  let response = try await client.listTopicSubscriptions(
    topic: "projects/\(projectID)/topics/\(topicID)"
  )
  for sub in response.subscriptions {
    print("Subscription: \(sub)")
  }
  return response.subscriptions
}
// [END pubsub_list_topic_subscriptions]

// [START pubsub_delete_topic]
public func deleteTopic(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String
) async throws {
  try await client.deleteTopic(topic: "projects/\(projectID)/topics/\(topicID)")
  print("Deleted topic \(topicID)")
}
// [END pubsub_delete_topic]

// [START pubsub_detach_subscription]
public func detachSubscription(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  subscriptionID: String
) async throws {
  _ = try await client.detachSubscription(
    request: DetachSubscriptionRequest().with {
      $0.subscription = "projects/\(projectID)/subscriptions/\(subscriptionID)"
    }
  )
  print("Detached subscription \(subscriptionID)")
}
// [END pubsub_detach_subscription]

// [START pubsub_create_topic_with_schema]
public func createTopicWithSchema(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String,
  schemaID: String,
  encoding: Encoding = .json
) async throws -> Topic {
  let topic = try await client.createTopic(
    request: Topic().with {
      $0.name = "projects/\(projectID)/topics/\(topicID)"
      $0.schemaSettings = SchemaSettings().with { settings in
        settings.schema = "projects/\(projectID)/schemas/\(schemaID)"
        settings.encoding = encoding
      }
    }
  )
  print("Created topic with schema: \(topic.name)")
  return topic
}
// [END pubsub_create_topic_with_schema]

// [START pubsub_create_topic_with_schema_revisions]
public func createTopicWithSchemaRevisions(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String,
  schemaID: String,
  firstRevisionID: String,
  lastRevisionID: String,
  encoding: Encoding = .json
) async throws -> Topic {
  let topic = try await client.createTopic(
    request: Topic().with {
      $0.name = "projects/\(projectID)/topics/\(topicID)"
      $0.schemaSettings = SchemaSettings().with { settings in
        settings.schema = "projects/\(projectID)/schemas/\(schemaID)"
        settings.firstRevisionId = firstRevisionID
        settings.lastRevisionId = lastRevisionID
        settings.encoding = encoding
      }
    }
  )
  print("Created topic with schema revisions: \(topic.name)")
  return topic
}
// [END pubsub_create_topic_with_schema_revisions]

// [START pubsub_update_topic_schema]
public func updateTopicSchemaRevisions(
  client: any Clients.TopicAdminProtocol,
  projectID: String,
  topicID: String,
  schemaID: String,
  firstRevisionID: String,
  lastRevisionID: String
) async throws -> Topic {
  let topic = try await client.updateTopic(
    request: UpdateTopicRequest().with {
      $0.topic = Topic().with { topic in
        topic.name = "projects/\(projectID)/topics/\(topicID)"
        topic.schemaSettings = SchemaSettings().with { settings in
          settings.schema = "projects/\(projectID)/schemas/\(schemaID)"
          settings.firstRevisionId = firstRevisionID
          settings.lastRevisionId = lastRevisionID
        }
      }
      $0.updateMask = GoogleWKT.WKTFieldMask().with { mask in
        mask.paths = [
          "schema_settings.first_revision_id",
          "schema_settings.last_revision_id",
        ]
      }
    }
  )
  print("Updated topic schema revisions: \(topic.name)")
  return topic
}
// [END pubsub_update_topic_schema]
