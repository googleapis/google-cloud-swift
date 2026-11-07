# Google Cloud Client Libraries for Swift - Cloud Datastore API

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-datastore%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-cloud-datastore)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-datastore%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-cloud-datastore)

Cloud Datastore is a highly scalable NoSQL database for your applications.

## Overview

This library provides an idiomatic Swift veneer (`DatastoreClient`) for Google Cloud Datastore data-plane operations (`google.datastore.v1`). For control-plane administration (index management and entity import/export), use `GoogleCloudDatastoreAdminV1` (`swift-google-datastore-admin-v1`).

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-cloud-datastore` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-cloud-datastore.git --from 0.6.0
```

Then add `GoogleCloudDatastore` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudDatastore <target-name> --package swift-google-cloud-datastore
```

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
