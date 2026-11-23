# Google Cloud Client Libraries for Swift - Cloud Pub/Sub Data-Plane Client

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-pubsub%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-cloud-pubsub)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-pubsub%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-cloud-pubsub)

Google Cloud Pub/Sub is a fully-managed real-time messaging service that allows
you to send and receive messages between independent applications.

## Overview

`GoogleCloudPubSub` implements high-throughput gRPC data-plane clients for
publishing and subscribing to Pub/Sub topics and subscriptions:

- `PublisherClient` / `Publisher`: Batched, ordered, flow-controlled, compressed,
  and hedged publishing.
- `BlockingPublisherClient`: Lightweight unbatched single-message publishing.
- `SubscriberClient`: Streaming pull consumption (`AsyncSequence`), adaptive lease
  management, exactly-once delivery settlement (`ackWithResult` / `nackWithResult`),
  per-stream flow control, keepalives, and managed unary `pull`.

For administrative CRUD operations on topics, subscriptions, snapshots, schemas,
and IAM policies, use the separate `GoogleCloudPubSubV1` package
(`swift-google-pubsub-v1`).

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-cloud-pubsub` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-cloud-pubsub.git --from 0.1.0
```

Then add `GoogleCloudPubSub` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudPubSub <target-name> --package swift-google-cloud-pubsub
```

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
