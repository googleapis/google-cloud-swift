# ``GoogleCloudPubSub``

High-throughput Swift 6 gRPC client library for publishing and subscribing to
Google Cloud Pub/Sub topics and subscriptions.

## Overview

`GoogleCloudPubSub` provides the performance-critical data-plane clients for
Google Cloud Pub/Sub:

- ``PublisherClient`` and ``Publisher``: Asynchronous batched publishing with
  automatic per-key ordering (`orderingKey`), corking and recovery
  (`resumePublishing(orderingKey:options:)`), local flow control, `gzip` payload
  compression, and latency-based request hedging.
- ``BlockingPublisherClient``: Unbatched unary single-message publishing for
  low-throughput or serverless callers.
- ``SubscriberClient`` and ``MessageStream``: Optimistic `StreamingPull`
  consumption via Swift's `AsyncSequence`, adaptive 99th-percentile lease
  management, dynamic exactly-once delivery settlement
  (`ackWithResult(options:)` / `nackWithResult(options:)`), per-stream flow
  control, keepalives, deterministic shutdown, and managed unary
  ``SubscriberClient/pull(subscription:options:)``.

For administrative operations on topics, subscriptions, snapshots, schemas, and
IAM policies, use the separate `GoogleCloudPubSubV1` package (`TopicAdminClient`,
`SubscriptionAdminClient`, and `SchemaServiceClient`).

## Quickstart

@Snippet(path: "PublisherQuickstart")

@Snippet(path: "SubscriberSubscribe")

## Topics

### Essentials

- <doc:BatchingOrderingAndHedging>
- <doc:StreamingAndExactlyOnce>
- <doc:Mocking>
- <doc:EmulatorAndEndpoints>
- <doc:RetriesAndIdempotency>
- <doc:ErrorHandling>
- <doc:Observability>

### Publishing

- ``PublisherClient``
- ``Publisher``
- ``BlockingPublisherClient``
- ``Message``
- ``PublishHandle``
- ``PublishResult``
- ``FlushResult``
- ``ResumePublishingResult``

### Subscribing & Settlement

- ``SubscriberClient``
- ``MessageStream``
- ``ReceivedMessage``
- ``PullResult``
- ``AckResult``
- ``AckQueuedResult``
- ``NackQueuedResult``
- ``SettlementStatus``
- ``AckError``

### Configuration & Errors

- ``PublisherClientOptions``
- ``TopicPublisherOptions``
- ``BatchingOptions``
- ``PublisherFlowControlOptions``
- ``FlowControlLimitExceededBehavior``
- ``CompressionOptions``
- ``HedgingOptions``
- ``PublishOptions``
- ``FlushOptions``
- ``ResumePublishingOptions``
- ``PublisherShutdownOptions``
- ``PublisherClientShutdownOptions``
- ``BlockingPublisherClientOptions``
- ``BlockingPublishOptions``
- ``SubscriberClientOptions``
- ``SubscribeOptions``
- ``PullOptions``
- ``SubscriberShutdownOptions``
- ``ShutdownBehavior``
- ``AckOptions``
- ``NackOptions``
- ``PubSubRetryPolicy``
- ``PubSubError``
- ``FlowControlLimitReason``

### Mocking Protocols

- ``Clients/PublisherClientProtocol``
- ``Clients/PublisherProtocol``
- ``Clients/BlockingPublisherProtocol``
- ``Clients/SubscriberProtocol``
- ``MessageStreamProtocol``
- ``AckHandlerProtocol``
