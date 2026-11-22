# Emulator and Endpoints

Configure `GoogleCloudPubSub` for the Pub/Sub emulator, regional endpoints, Private
Service Connect, and Google Cloud Universe Domains.

## Using the Pub/Sub Emulator (`PUBSUB_EMULATOR_HOST`)

When the `PUBSUB_EMULATOR_HOST` environment variable is set (for example
`127.0.0.1:8085` or `http://localhost:8085`), both `GoogleCloudPubSub` and
`GoogleCloudPubSubV1` automatically:

1. Resolve requests to a plaintext HTTP/2 (or HTTP/1.1 for Admin REST) channel to
   that host and port when `GoogleGax.ClientOptions.endpoint` is `nil` or empty.
2. Default to anonymous credentials when `GoogleGax.ClientOptions.credentials` is
   `nil`, bypassing Application Default Credentials discovery.

Explicitly setting `ClientOptions.endpoint` always takes precedence over
`PUBSUB_EMULATOR_HOST`. Likewise, explicitly setting `ClientOptions.credentials`
preserves your configured credentials even when using the emulator.

> Note: Configuring the emulator never alters client validation or logging configuration.

## Regional Endpoints and Universe Domain

Use `GoogleGax.ClientOptions.endpoint` to target locational or regional endpoints:

```swift
var clientOptions = PublisherClientOptions()
clientOptions.client.endpoint = "https://us-central1-pubsub.googleapis.com"
```

To target a non-default cloud universe domain, configure
`ClientOptions.universeDomain` or set `GOOGLE_CLOUD_UNIVERSE_DOMAIN`.
`GoogleCloudPubSub` validates credential universe-domain consistency before
issuing RPCs.
