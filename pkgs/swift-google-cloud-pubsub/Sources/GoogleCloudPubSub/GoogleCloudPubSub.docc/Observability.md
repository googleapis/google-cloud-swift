# Observability

Configure `swift-log` structured diagnostics matching generated Google Cloud
Swift libraries and review the pre-`1.0` GA OpenTelemetry roadmap.

## Structured Logging (`swift-log`)

Pass a `Logging.Logger` through `ClientOptions.logger` on
``PublisherClientOptions``, ``BlockingPublisherClientOptions``, or
``SubscriberClientOptions`` to capture structured RPC lifecycle logs.

Every log record attaches consistent Google Cloud metadata keys:

- `gcp.artifact.id`: `"google-cloud-pubsub"`
- `gcp.client.service`: `"pubsub"`
- `gcp.client.version`: package version string
- `gcp.client.repo`: `"googleapis/google-cloud-swift"`
- `gcp.resource.destination.id`: `//pubsub.googleapis.com/<topic-or-subscription>`
- `rpc.method`: real gRPC service method names such as
  `"google.pubsub.v1.Publisher/Publish"`,
  `"google.pubsub.v1.Subscriber/StreamingPull"`,
  `"google.pubsub.v1.Subscriber/Pull"`,
  `"google.pubsub.v1.Subscriber/Acknowledge"`, or
  `"google.pubsub.v1.Subscriber/ModifyAckDeadline"`

Terminal operation errors are logged once at the public operation boundary;
`GoogleCloudPubSub` never logs message payloads, attributes, or bearer tokens.

## OpenTelemetry & Metrics Roadmap

OpenTelemetry distributed traces and CLO v1 metrics are scheduled ahead of `1.0`
GA once shared OpenTelemetry providers land in `GoogleGax`.
