# Google Cloud Client Libraries for Swift - GAX gRPC Transport

gRPC transport infrastructure for Google Cloud client libraries in Swift.

## Overview

`GoogleGaxGRPC` provides the gRPC transport layer built on `grpc-swift-2` and
`SwiftProtobuf` for Google Cloud client libraries that use gRPC (such as the
Google Cloud Storage Control plane).

This package is separated from `swift-google-gax` so that HTTP/REST client
libraries depending only on `GoogleGax` do not pull `grpc-swift-2`,
`grpc-swift-nio-transport`, `grpc-swift-protobuf`, or `swift-protobuf` into
their Swift Package Manager dependency graph.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-gax-grpc` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-gax-grpc.git --from 0.3.0
```

Then add `GoogleGaxGRPC` to your target's dependencies:

```bash
swift package add-target-dependency GoogleGaxGRPC <target-name> --package swift-google-gax-grpc
```

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
