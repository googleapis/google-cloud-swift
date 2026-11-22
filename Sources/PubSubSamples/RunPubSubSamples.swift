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
import GoogleCloudPubSubV1
import GoogleWKT

fileprivate let lowerCaseAlphanumeric = "abcdefghijklmnopqrstuvwxyz0123456789"
fileprivate let sampleAvroSchema = """
  {
    "type": "record",
    "name": "StateProvince",
    "namespace": "utilities",
    "fields": [
      {"name": "name", "type": "string"},
      {"name": "post_abbr", "type": "string"}
    ]
  }
  """
fileprivate let updatedAvroSchema = """
  {
    "type": "record",
    "name": "StateProvince",
    "namespace": "utilities",
    "fields": [
      {"name": "name", "type": "string"},
      {"name": "post_abbr", "type": "string", "default": ""}
    ]
  }
  """

/// Generates a valid Cloud Pub/Sub resource identifier with the SDK testing prefix.
public func randomPubSubResourceID(prefix: String = "swift-sdk-testing-") -> String {
  let suffix = String((0..<12).map { _ in lowerCaseAlphanumeric.randomElement()! })
  return prefix + suffix
}

/// Executes topic, subscription, snapshot, seek, IAM, publisher, and subscriber samples.
public func runPubSubCoreSamples(
  topicAdmin: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  subscriptionAdmin: any GoogleCloudPubSubV1.Clients.SubscriptionAdminProtocol,
  publisherClient: any GoogleCloudPubSub.Clients.PublisherClientProtocol,
  subscriberClient: any GoogleCloudPubSub.Clients.SubscriberProtocol,
  projectID: String,
  serviceAccount: String,
  cleanupBag: inout PubSubSampleCleanupBag
) async throws {
  let quickTopicID = randomPubSubResourceID(prefix: "swift-topic-")
  cleanupBag.topics.append("projects/\(projectID)/topics/\(quickTopicID)")
  _ = try await quickstartCreateTopic(
    projectID: projectID, topicID: quickTopicID, client: topicAdmin)

  let topicID = randomPubSubResourceID(prefix: "swift-topic-")
  let topicName = "projects/\(projectID)/topics/\(topicID)"
  cleanupBag.topics.append(topicName)
  _ = try await createTopic(client: topicAdmin, projectID: projectID, topicID: topicID)
  _ = try await listTopics(client: topicAdmin, projectID: projectID)

  let subID = randomPubSubResourceID(prefix: "swift-sub-")
  cleanupBag.subscriptions.append("projects/\(projectID)/subscriptions/\(subID)")
  _ = try await createPullSubscription(
    client: subscriptionAdmin,
    projectID: projectID,
    topicID: topicID,
    subscriptionID: subID
  )
  _ = try await listTopicSubscriptions(client: topicAdmin, projectID: projectID, topicID: topicID)
  _ = try await listSubscriptions(client: subscriptionAdmin, projectID: projectID)

  _ = try await getTopicPolicy(client: topicAdmin, projectID: projectID, topicID: topicID)
  _ = try await setTopicPolicy(
    client: topicAdmin,
    projectID: projectID,
    topicID: topicID,
    role: "roles/pubsub.viewer",
    member: "serviceAccount:\(serviceAccount)"
  )
  _ = try await testTopicPermissions(client: topicAdmin, projectID: projectID, topicID: topicID)

  _ = try await getSubscriptionPolicy(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID
  )
  _ = try await setSubscriptionPolicy(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID,
    role: "roles/pubsub.viewer",
    member: "serviceAccount:\(serviceAccount)"
  )
  _ = try await testSubscriptionPermissions(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID
  )

  let snapID = randomPubSubResourceID(prefix: "swift-snap-")
  cleanupBag.snapshots.append("projects/\(projectID)/snapshots/\(snapID)")
  _ = try await createSnapshot(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID,
    snapshotID: snapID
  )
  _ = try await listSnapshots(client: subscriptionAdmin, projectID: projectID)
  try await seekToSnapshot(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID,
    snapshotID: snapID
  )
  try await seekToTimestamp(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID,
    time: GoogleWKT.WKTTimestamp(Date())
  )
  try await deleteSnapshot(client: subscriptionAdmin, projectID: projectID, snapshotID: snapID)

  let publisher = try publisherClient.publisher(topic: topicName)
  _ = try await publishMessages(publisher: publisher, payloads: ["hello-1", "hello-2"])
  _ = try await publishWithCustomAttributes(publisher: publisher)
  _ = await publishWithErrorHandler(publisher: publisher, payload: "hello-3")
  _ = try await publisher.flush()
  _ = try await subscribeAsyncPull(
    subscriber: subscriberClient,
    subscription: "projects/\(projectID)/subscriptions/\(subID)",
    maxMessages: 2
  )
  _ = try await subscriberSyncPull(
    subscriber: subscriberClient,
    subscription: "projects/\(projectID)/subscriptions/\(subID)",
    maxMessages: 2
  )
  try await detachSubscription(
    client: topicAdmin,
    projectID: projectID,
    subscriptionID: subID
  )
  try await deleteSubscription(
    client: subscriptionAdmin,
    projectID: projectID,
    subscriptionID: subID
  )
  try await deleteTopic(client: topicAdmin, projectID: projectID, topicID: topicID)
}

/// Executes Pub/Sub schema lifecycle and topic validation samples against `schemaClient`.
public func runPubSubSchemaSamples(
  schemaClient: any GoogleCloudPubSubV1.Clients.SchemaServiceProtocol,
  topicAdmin: any GoogleCloudPubSubV1.Clients.TopicAdminProtocol,
  projectID: String,
  cleanupBag: inout PubSubSampleCleanupBag
) async throws {
  let schemaID = randomPubSubResourceID(prefix: "swift-schema-")
  cleanupBag.schemas.append("projects/\(projectID)/schemas/\(schemaID)")

  _ = try await validateSchema(
    client: schemaClient,
    projectID: projectID,
    schemaType: .avro,
    definition: sampleAvroSchema
  )
  let created = try await createAvroSchema(
    client: schemaClient,
    projectID: projectID,
    schemaID: schemaID,
    avscDefinition: sampleAvroSchema
  )
  let committed = try await commitAvroSchema(
    client: schemaClient,
    projectID: projectID,
    schemaID: schemaID,
    avscDefinition: updatedAvroSchema
  )
  _ = try await getSchema(client: schemaClient, projectID: projectID, schemaID: schemaID)
  if !committed.revisionId.isEmpty {
    _ = try await getSchemaRevision(
      client: schemaClient,
      projectID: projectID,
      schemaID: schemaID,
      revisionID: committed.revisionId
    )
  }
  _ = try await listSchemas(client: schemaClient, projectID: projectID)
  _ = try await listSchemaRevisions(client: schemaClient, projectID: projectID, schemaID: schemaID)
  let validPayload = try JSONEncoder().encode(StateProvinceRecord(name: "Oregon", postAbbr: "OR"))
  _ = try await validateMessage(
    client: schemaClient,
    projectID: projectID,
    schemaID: schemaID,
    payload: validPayload,
    encoding: .json
  )

  let schemaTopicID = randomPubSubResourceID(prefix: "swift-schema-topic-")
  cleanupBag.topics.append("projects/\(projectID)/topics/\(schemaTopicID)")
  let firstRev = created.revisionId
  let lastRev = committed.revisionId.isEmpty ? firstRev : committed.revisionId
  _ = try await createTopicWithSchema(
    client: topicAdmin,
    projectID: projectID,
    topicID: schemaTopicID,
    schemaID: schemaID,
    encoding: .json
  )
  if !firstRev.isEmpty && !lastRev.isEmpty {
    _ = try await updateTopicSchemaRevisions(
      client: topicAdmin,
      projectID: projectID,
      topicID: schemaTopicID,
      schemaID: schemaID,
      firstRevisionID: firstRev,
      lastRevisionID: lastRev
    )
    _ = try await rollbackSchema(
      client: schemaClient,
      projectID: projectID,
      schemaID: schemaID,
      revisionID: firstRev
    )
    _ = try await deleteSchemaRevision(
      client: schemaClient,
      projectID: projectID,
      schemaID: schemaID,
      revisionID: lastRev
    )
  }
  try await deleteTopic(client: topicAdmin, projectID: projectID, topicID: schemaTopicID)
  try await deleteSchema(client: schemaClient, projectID: projectID, schemaID: schemaID)
}
