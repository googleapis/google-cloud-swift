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
import GoogleGax
import GoogleIAMV1
import PubSubSamples
import Testing

private actor SampleCallRecorder {
  var publishedMessages: [Message] = []
  var ackedIDs: [String] = []
  var nackedIDs: [String] = []
  var createdTopics: [Topic] = []
  var updatedTopics: [UpdateTopicRequest] = []
  var deletedTopics: [String] = []
  var detachedSubscriptions: [String] = []
  var createdSubscriptions: [Subscription] = []
  var updatedSubscriptions: [UpdateSubscriptionRequest] = []
  var modifiedPushConfigs: [ModifyPushConfigRequest] = []
  var deletedSubscriptions: [String] = []
  var createdSnapshots: [CreateSnapshotRequest] = []
  var deletedSnapshots: [String] = []
  var seekRequests: [SeekRequest] = []
  var createdSchemas: [CreateSchemaRequest] = []
  var committedSchemas: [CommitSchemaRequest] = []
  var rolledBackSchemas: [RollbackSchemaRequest] = []
  var deletedSchemaRevisions: [String] = []
  var deletedSchemas: [String] = []
  var iamPolicy: GoogleIAMV1.Policy = GoogleIAMV1.Policy()

  func appendPublished(_ message: Message) -> String {
    self.publishedMessages.append(message)
    return "msg-\(self.publishedMessages.count)"
  }

  func recordAck(_ id: String) {
    self.ackedIDs.append(id)
  }

  func recordNack(_ id: String) {
    self.nackedIDs.append(id)
  }

  func addTopic(_ topic: Topic) -> Topic {
    self.createdTopics.append(topic)
    return topic
  }

  func updateTopic(_ req: UpdateTopicRequest) -> Topic {
    self.updatedTopics.append(req)
    return req.topic ?? Topic()
  }

  func deleteTopic(_ name: String) {
    self.deletedTopics.append(name)
  }

  func detachSub(_ name: String) {
    self.detachedSubscriptions.append(name)
  }

  func addSubscription(_ sub: Subscription) -> Subscription {
    self.createdSubscriptions.append(sub)
    return sub
  }

  func updateSubscription(_ req: UpdateSubscriptionRequest) -> Subscription {
    self.updatedSubscriptions.append(req)
    return req.subscription ?? Subscription()
  }

  func modifyPush(_ req: ModifyPushConfigRequest) {
    self.modifiedPushConfigs.append(req)
  }

  func deleteSub(_ name: String) {
    self.deletedSubscriptions.append(name)
  }

  func createSnap(_ req: CreateSnapshotRequest) -> Snapshot {
    self.createdSnapshots.append(req)
    return Snapshot().with {
      $0.name = req.name
      $0.topic = "projects/p/topics/t"
    }
  }

  func deleteSnap(_ name: String) {
    self.deletedSnapshots.append(name)
  }

  func recordSeek(_ req: SeekRequest) {
    self.seekRequests.append(req)
  }

  func setPolicy(_ policy: GoogleIAMV1.Policy) -> GoogleIAMV1.Policy {
    self.iamPolicy = policy
    return policy
  }

  func createSchema(_ req: CreateSchemaRequest) -> Schema {
    self.createdSchemas.append(req)
    return (req.schema ?? Schema()).with {
      $0.name = "\(req.parent)/schemas/\(req.schemaId)"
      $0.revisionId = "rev-1"
    }
  }

  func commitSchema(_ req: CommitSchemaRequest) -> Schema {
    self.committedSchemas.append(req)
    return (req.schema ?? Schema()).with {
      $0.name = req.name
      $0.revisionId = "rev-2"
    }
  }

  func rollbackSchema(_ req: RollbackSchemaRequest) -> Schema {
    self.rolledBackSchemas.append(req)
    return Schema().with {
      $0.name = req.name
      $0.revisionId = req.revisionId
    }
  }

  func deleteSchemaRevision(_ req: DeleteSchemaRevisionRequest) -> Schema {
    self.deletedSchemaRevisions.append(req.name)
    return Schema().with { $0.name = req.name }
  }

  func deleteSchema(_ name: String) {
    self.deletedSchemas.append(name)
  }
}

private struct MockAckHandler: AckHandlerProtocol {
  let id: String
  let recorder: SampleCallRecorder

  func ack(options: AckOptions) -> AckQueuedResult {
    Task { await self.recorder.recordAck(self.id) }
    return AckQueuedResult()
  }

  func nack(options: NackOptions) -> NackQueuedResult {
    Task { await self.recorder.recordNack(self.id) }
    return NackQueuedResult()
  }

  func ackWithResult(options: AckOptions) async throws -> AckResult {
    await self.recorder.recordAck(self.id)
    return AckResult(status: .success)
  }

  func nackWithResult(options: NackOptions) async throws -> AckResult {
    await self.recorder.recordNack(self.id)
    return AckResult(status: .success)
  }
}

private actor PauseControl {
  var isPaused = true

  func resume() {
    self.isPaused = false
  }
}

private struct MockPublisher: GoogleCloudPubSub.Clients.PublisherProtocol {
  let topic: String
  let recorder: SampleCallRecorder
  let pauseControl: PauseControl?

  init(topic: String, recorder: SampleCallRecorder, pauseOnFirstKey: Bool = false) {
    self.topic = topic
    self.recorder = recorder
    self.pauseControl = pauseOnFirstKey ? PauseControl() : nil
  }

  func startPublish(_ message: Message, options: PublishOptions) async throws -> PublishHandle {
    if let pauseControl = self.pauseControl, !message.orderingKey.isEmpty,
      await pauseControl.isPaused
    {
      return PublishHandle(
        resolvedResult: .failure(PubSubError.orderingKeyPaused(orderingKey: message.orderingKey))
      )
    }
    let id = await self.recorder.appendPublished(message)
    return PublishHandle(resolvedResult: .success(PublishResult(messageID: id)))
  }

  func flush(options: FlushOptions) async throws -> FlushResult {
    FlushResult()
  }

  func resumePublishing(
    orderingKey: String,
    options: ResumePublishingOptions
  ) async throws -> ResumePublishingResult {
    await self.pauseControl?.resume()
    return ResumePublishingResult()
  }

  func shutdown(options: PublisherShutdownOptions) async throws -> ShutdownResult {
    ShutdownResult()
  }
}

private struct MockPublisherClient: GoogleCloudPubSub.Clients.PublisherClientProtocol {
  let recorder: SampleCallRecorder

  func publisher(topic: String, options: TopicPublisherOptions) throws
    -> any GoogleCloudPubSub.Clients.PublisherProtocol
  {
    MockPublisher(topic: topic, recorder: self.recorder)
  }

  func shutdown(options: PublisherClientShutdownOptions) async throws -> ShutdownResult {
    ShutdownResult()
  }
}

private struct MockSubscriber: GoogleCloudPubSub.Clients.SubscriberProtocol {
  let recorder: SampleCallRecorder
  let messages: [Message]
  let failStream: Bool

  init(recorder: SampleCallRecorder, messages: [Message], failStream: Bool = false) {
    self.recorder = recorder
    self.messages = messages
    self.failStream = failStream
  }

  func subscribe(subscription: String, options: SubscribeOptions) throws
    -> any MessageStreamProtocol
  {
    if self.failStream {
      return MessageStream(
        next: { throw GoogleGax.RequestError.unimplemented },
        onStop: { _ in ShutdownResult() }
      )
    }
    let received = self.messages.enumerated().map { idx, msg in
      ReceivedMessage(
        message: msg,
        isExactlyOnce: true,
        ackHandler: MockAckHandler(
          id: msg.messageID.isEmpty ? "id-\(idx)" : msg.messageID, recorder: self.recorder)
      )
    }
    return MessageStream(messages: received)
  }

  func pull(subscription: String, options: PullOptions) async throws -> PullResult {
    let received = self.messages.enumerated().map { idx, msg in
      ReceivedMessage(
        message: msg,
        isExactlyOnce: true,
        ackHandler: MockAckHandler(
          id: msg.messageID.isEmpty ? "pull-\(idx)" : msg.messageID, recorder: self.recorder)
      )
    }
    return PullResult(messages: received)
  }
}

private struct MockTopicAdmin: GoogleCloudPubSubV1.Clients.TopicAdminProtocol {
  let recorder: SampleCallRecorder

  func createTopic(request: Topic, options: GoogleGax.RequestOptions) async throws -> Topic {
    await self.recorder.addTopic(request)
  }

  func getTopic(request: GetTopicRequest, options: GoogleGax.RequestOptions) async throws -> Topic {
    Topic().with {
      $0.name = request.topic
      $0.schemaSettings = SchemaSettings().with { settings in
        settings.schema = "projects/p/schemas/s"
        settings.encoding = .json
      }
    }
  }

  func updateTopic(request: UpdateTopicRequest, options: GoogleGax.RequestOptions) async throws
    -> Topic
  {
    await self.recorder.updateTopic(request)
  }

  func listTopics(request: ListTopicsRequest, options: GoogleGax.RequestOptions) async throws
    -> ListTopicsResponse
  {
    ListTopicsResponse().with {
      $0.topics = [Topic().with { topic in topic.name = "\(request.project)/topics/t1" }]
    }
  }

  func listTopicSubscriptions(
    request: ListTopicSubscriptionsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> ListTopicSubscriptionsResponse {
    ListTopicSubscriptionsResponse().with {
      $0.subscriptions = ["projects/p/subscriptions/sub1"]
    }
  }

  func deleteTopic(request: DeleteTopicRequest, options: GoogleGax.RequestOptions) async throws {
    await self.recorder.deleteTopic(request.topic)
  }

  func detachSubscription(
    request: DetachSubscriptionRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> DetachSubscriptionResponse {
    await self.recorder.detachSub(request.subscription)
    return DetachSubscriptionResponse()
  }

  func getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.Policy {
    await self.recorder.iamPolicy
  }

  func setIamPolicy(
    request: GoogleIAMV1.SetIamPolicyRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.Policy {
    await self.recorder.setPolicy(request.policy ?? GoogleIAMV1.Policy())
  }

  func testIamPermissions(
    request: GoogleIAMV1.TestIamPermissionsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.TestIamPermissionsResponse {
    GoogleIAMV1.TestIamPermissionsResponse().with {
      $0.permissions = request.permissions
    }
  }
}

private struct MockSubscriptionAdmin: GoogleCloudPubSubV1.Clients.SubscriptionAdminProtocol {
  let recorder: SampleCallRecorder

  func createSubscription(request: Subscription, options: GoogleGax.RequestOptions) async throws
    -> Subscription
  {
    await self.recorder.addSubscription(request)
  }

  func updateSubscription(
    request: UpdateSubscriptionRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> Subscription {
    await self.recorder.updateSubscription(request)
  }

  func modifyPushConfig(
    request: ModifyPushConfigRequest,
    options: GoogleGax.RequestOptions
  ) async throws {
    await self.recorder.modifyPush(request)
  }

  func listSubscriptions(
    request: ListSubscriptionsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> ListSubscriptionsResponse {
    ListSubscriptionsResponse().with {
      $0.subscriptions = [
        Subscription().with { sub in sub.name = "\(request.project)/subscriptions/s1" }
      ]
    }
  }

  func deleteSubscription(
    request: DeleteSubscriptionRequest,
    options: GoogleGax.RequestOptions
  ) async throws {
    await self.recorder.deleteSub(request.subscription)
  }

  func createSnapshot(request: CreateSnapshotRequest, options: GoogleGax.RequestOptions)
    async throws -> Snapshot
  {
    await self.recorder.createSnap(request)
  }

  func listSnapshots(request: ListSnapshotsRequest, options: GoogleGax.RequestOptions) async throws
    -> ListSnapshotsResponse
  {
    ListSnapshotsResponse().with {
      $0.snapshots = [
        Snapshot().with { snap in snap.name = "\(request.project)/snapshots/snap1" }
      ]
    }
  }

  func deleteSnapshot(request: DeleteSnapshotRequest, options: GoogleGax.RequestOptions)
    async throws
  {
    await self.recorder.deleteSnap(request.snapshot)
  }

  func seek(request: SeekRequest, options: GoogleGax.RequestOptions) async throws -> SeekResponse {
    await self.recorder.recordSeek(request)
    return SeekResponse()
  }

  func getIamPolicy(
    request: GoogleIAMV1.GetIamPolicyRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.Policy {
    await self.recorder.iamPolicy
  }

  func setIamPolicy(
    request: GoogleIAMV1.SetIamPolicyRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.Policy {
    await self.recorder.setPolicy(request.policy ?? GoogleIAMV1.Policy())
  }

  func testIamPermissions(
    request: GoogleIAMV1.TestIamPermissionsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> GoogleIAMV1.TestIamPermissionsResponse {
    GoogleIAMV1.TestIamPermissionsResponse().with {
      $0.permissions = request.permissions
    }
  }
}

private struct MockSchemaService: GoogleCloudPubSubV1.Clients.SchemaServiceProtocol {
  let recorder: SampleCallRecorder

  func createSchema(request: CreateSchemaRequest, options: GoogleGax.RequestOptions) async throws
    -> Schema
  {
    await self.recorder.createSchema(request)
  }

  func getSchema(request: GetSchemaRequest, options: GoogleGax.RequestOptions) async throws
    -> Schema
  {
    Schema().with {
      $0.name = request.name
      $0.type = .avro
      $0.revisionId = "rev-1"
    }
  }

  func listSchemas(request: ListSchemasRequest, options: GoogleGax.RequestOptions) async throws
    -> ListSchemasResponse
  {
    ListSchemasResponse().with {
      $0.schemas = [Schema().with { schema in schema.name = "\(request.parent)/schemas/s1" }]
    }
  }

  func listSchemaRevisions(
    request: ListSchemaRevisionsRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> ListSchemaRevisionsResponse {
    ListSchemaRevisionsResponse().with {
      $0.schemas = [
        Schema().with { revision in
          revision.name = request.name
          revision.revisionId = "rev-1"
        },
        Schema().with { revision in
          revision.name = request.name
          revision.revisionId = "rev-2"
        },
      ]
    }
  }

  func commitSchema(request: CommitSchemaRequest, options: GoogleGax.RequestOptions) async throws
    -> Schema
  {
    await self.recorder.commitSchema(request)
  }

  func rollbackSchema(request: RollbackSchemaRequest, options: GoogleGax.RequestOptions)
    async throws -> Schema
  {
    await self.recorder.rollbackSchema(request)
  }

  func deleteSchemaRevision(
    request: DeleteSchemaRevisionRequest,
    options: GoogleGax.RequestOptions
  ) async throws -> Schema {
    await self.recorder.deleteSchemaRevision(request)
  }

  func deleteSchema(request: DeleteSchemaRequest, options: GoogleGax.RequestOptions) async throws {
    await self.recorder.deleteSchema(request.name)
  }

  func validateSchema(request: ValidateSchemaRequest, options: GoogleGax.RequestOptions)
    async throws -> ValidateSchemaResponse
  {
    ValidateSchemaResponse()
  }

  func validateMessage(request: ValidateMessageRequest, options: GoogleGax.RequestOptions)
    async throws -> ValidateMessageResponse
  {
    ValidateMessageResponse()
  }
}

@Suite struct PubSubSamplesHermeticTests {
  @Test func publisherSamplesWork() async throws {
    let recorder = SampleCallRecorder()
    let publisher = MockPublisher(topic: "projects/p/topics/t", recorder: recorder)
    let client = MockPublisherClient(recorder: recorder)

    let ids = try await PubSubSamples.publishMessages(publisher: publisher, payloads: ["a", "b"])
    #expect(ids == ["msg-1", "msg-2"])

    _ = try await PubSubSamples.publishWithCustomAttributes(publisher: publisher)
    _ = await PubSubSamples.publishWithErrorHandler(publisher: publisher, payload: "ok")
    _ = try await PubSubSamples.publishWithBatchSettings(
      publisherClient: client, topic: "t", messages: ["x", "y"]
    )
    _ = try await PubSubSamples.publishWithOrderingKeys(publisher: publisher)

    let pausingPublisher = MockPublisher(
      topic: "projects/p/topics/t",
      recorder: recorder,
      pauseOnFirstKey: true
    )
    let resumed = try await PubSubSamples.resumePublishWithOrderingKeys(
      publisher: pausingPublisher, orderingKey: "k1", payload: "resumed"
    )
    #expect(!resumed.messageID.isEmpty)

    _ = try await PubSubSamples.publishWithRetrySettings(
      publisherClient: client, topic: "t", payload: "retry"
    )
    _ = try await PubSubSamples.publishWithFlowControl(
      publisherClient: client, topic: "t", payloads: ["fc"]
    )
    _ = try await PubSubSamples.publishWithCompression(publisherClient: client, topic: "t")
    _ = try await PubSubSamples.publishWithHedgingSettings(
      publisherClient: client, topic: "t", payload: "hedge"
    )

    let publishedCount = await recorder.publishedMessages.count
    #expect(publishedCount == 14)
  }

  @Test func subscriberSamplesWork() async throws {
    let recorder = SampleCallRecorder()
    var msg1 = Message(data: Data("hello".utf8), attributes: ["k": "v"])
    msg1.messageID = "m1"
    msg1.deliveryAttempt = 3
    let sub = MockSubscriber(recorder: recorder, messages: [msg1])

    #expect(
      try await PubSubSamples.subscribeAsyncPull(subscriber: sub, subscription: "s", maxMessages: 1)
        == ["m1"]
    )
    _ = try await PubSubSamples.subscribeWithCustomAttributes(subscriber: sub, subscription: "s")
    _ = try await PubSubSamples.subscribeWithConcurrencyControl(subscriber: sub, subscription: "s")
    _ = try await PubSubSamples.subscribeExactlyOnce(subscriber: sub, subscription: "s")
    let attempts = try await PubSubSamples.subscribeDeadLetterDeliveryAttempt(
      subscriber: sub, subscription: "s"
    )
    #expect(attempts == [3])
    _ = try await PubSubSamples.optimisticSubscribe(subscriber: sub, subscription: "s")
    _ = try await PubSubSamples.subscribeWithFlowSettings(subscriber: sub, subscription: "s")
    _ = try await PubSubSamples.subscriberSyncPull(subscriber: sub, subscription: "s")
    _ = try await PubSubSamples.subscriberSyncPullWithLease(subscriber: sub, subscription: "s")

    let errSub = MockSubscriber(recorder: recorder, messages: [], failStream: true)
    let (_, err) = await PubSubSamples.subscribeWithErrorListener(
      subscriber: errSub, subscription: "s"
    )
    #expect(err != nil)
  }

  @Test func adminSchemaPayloadAndIamSamplesWork() async throws {
    let recorder = SampleCallRecorder()
    let topicAdmin = MockTopicAdmin(recorder: recorder)
    let subAdmin = MockSubscriptionAdmin(recorder: recorder)
    let schemaClient = MockSchemaService(recorder: recorder)
    let pubClient = MockPublisherClient(recorder: recorder)
    let jsonPayload = try JSONEncoder().encode(StateProvinceRecord(name: "Maine", postAbbr: "ME"))
    let sub = MockSubscriber(
      recorder: recorder,
      messages: [
        Message(
          data: jsonPayload,
          attributes: [
            "googclient_schemaencoding": "JSON",
            "googclient_schemaname": "projects/p/schemas/s",
            "googclient_schemarevisionid": "rev-1",
          ]
        )
      ]
    )

    var bag = PubSubSampleCleanupBag()
    try await PubSubSamples.runPubSubCoreSamples(
      topicAdmin: topicAdmin,
      subscriptionAdmin: subAdmin,
      publisherClient: pubClient,
      subscriberClient: sub,
      projectID: "p",
      serviceAccount: "sa@example.iam.gserviceaccount.com",
      cleanupBag: &bag
    )
    try await PubSubSamples.runPubSubSchemaSamples(
      schemaClient: schemaClient,
      topicAdmin: topicAdmin,
      projectID: "p",
      cleanupBag: &bag
    )

    // Remaining topic/subscription/schema/payload samples not covered by runPubSubCoreSamples/Schema:
    _ = try await PubSubSamples.createTopicWithSchemaRevisions(
      client: topicAdmin, projectID: "p", topicID: "t2", schemaID: "s",
      firstRevisionID: "r1", lastRevisionID: "r2"
    )
    _ = try await PubSubSamples.createPushSubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "push",
      pushEndpoint: "https://example.com/push"
    )
    _ = try await PubSubSamples.createUnwrappedPushSubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "nopush",
      pushEndpoint: "https://example.com/push"
    )
    try await PubSubSamples.updatePushConfig(
      client: subAdmin, projectID: "p", subscriptionID: "push",
      pushEndpoint: "https://example.com/push2"
    )
    _ = try await PubSubSamples.createBigQuerySubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "bq",
      bigqueryTableID: "p:ds.tbl"
    )
    _ = try await PubSubSamples.createCloudStorageSubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "gcs",
      bucketName: "bucket"
    )
    _ = try await PubSubSamples.createDeadLetterSubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "dl",
      deadLetterTopicID: "dlt"
    )
    _ = try await PubSubSamples.updateDeadLetterSubscription(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "dl",
      deadLetterTopicID: "dlt2"
    )
    _ = try await PubSubSamples.removeDeadLetterPolicy(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "dl"
    )
    _ = try await PubSubSamples.createSubscriptionWithExactlyOnceDelivery(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "eod"
    )
    _ = try await PubSubSamples.createSubscriptionWithFilter(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "filt"
    )
    _ = try await PubSubSamples.enableSubscriptionOrdering(
      client: subAdmin, projectID: "p", topicID: "t", subscriptionID: "ord"
    )
    _ = try await PubSubSamples.createProtoSchema(
      client: schemaClient, projectID: "p", schemaID: "ps", protoDefinition: "syntax = \"proto3\";"
    )
    _ = try await PubSubSamples.commitProtoSchema(
      client: schemaClient, projectID: "p", schemaID: "ps", protoDefinition: "syntax = \"proto3\";"
    )

    let publisher = MockPublisher(topic: "projects/p/topics/t", recorder: recorder)
    let avroIDs = try await PubSubSamples.publishAvroRecords(
      topicAdmin: topicAdmin,
      publisher: publisher,
      projectID: "p",
      topicID: "t",
      records: [StateProvinceRecord(name: "Oregon", postAbbr: "OR")]
    )
    #expect(avroIDs.count == 1)
    let avroDecoded = try await PubSubSamples.subscribeAvroRecords(
      subscriber: sub, subscription: "s")
    #expect(avroDecoded == [StateProvinceRecord(name: "Maine", postAbbr: "ME")])
    let avroRevDecoded = try await PubSubSamples.subscribeAvroRecordsWithRevisions(
      subscriber: sub, schemaClient: schemaClient, subscription: "s"
    )
    #expect(avroRevDecoded == [StateProvinceRecord(name: "Maine", postAbbr: "ME")])
    let protoIDs = try await PubSubSamples.publishProtoMessages(
      topicAdmin: topicAdmin,
      publisher: publisher,
      projectID: "p",
      topicID: "t",
      records: [StateProvinceRecord(name: "Oregon", postAbbr: "OR")]
    )
    #expect(protoIDs.count == 1)
    let protoDecoded = try await PubSubSamples.subscribeProtoMessages(
      subscriber: sub, subscription: "s")
    #expect(protoDecoded == [StateProvinceRecord(name: "Maine", postAbbr: "ME")])

    await PubSubSamples.cleanupPubSubSampleResources(
      topicAdmin: topicAdmin, subscriptionAdmin: subAdmin, schemaClient: schemaClient, bag: bag
    )

    #expect(await recorder.createdTopics.count == 4)
    #expect(await recorder.updatedTopics.count == 1)
    #expect(await recorder.deletedTopics.count == 5)
    #expect(await recorder.detachedSubscriptions.count == 1)
    #expect(await recorder.createdSubscriptions.count == 9)
    #expect(await recorder.updatedSubscriptions.count == 2)
    #expect(await recorder.modifiedPushConfigs.count == 1)
    #expect(await recorder.createdSnapshots.count == 1)
    #expect(await recorder.seekRequests.count == 2)
    #expect(await recorder.createdSchemas.count == 2)
    #expect(await recorder.committedSchemas.count == 2)
    #expect(await recorder.rolledBackSchemas.count == 1)
    #expect(await recorder.deletedSchemaRevisions.count == 1)
    #expect(await recorder.deletedSchemas.count == 2)
    #expect(await recorder.iamPolicy.bindings.count == 2)
    #expect(await recorder.publishedMessages.count == 6)
  }
}
