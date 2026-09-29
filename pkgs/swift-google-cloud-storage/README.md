# Google Cloud Client Libraries for Swift - Storage API

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-storage%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-cloud-storage)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-cloud-storage%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-cloud-storage)

Cloud Storage is a managed service for storing unstructured data. Store any
amount of data and retrieve it as often as you like.

## Overview

This library implements types to work with Google Cloud Storage.

Use `StorageClient` to write (upload) and read (download) [objects]. A default
initialized `StorageClient` works in most cases. The client supports resumable
uploads, single-shot uploads, full and partial object reads. To provide data for
writes implement the `SeekableWriteObjectSource` or the `WriteObjectSource`
protocols.

Use `StorageControlClient` for other operations, including listing, deleting,
updating object metadata, object rewrites, and object composition. The same
type can be used to perform all operations on [buckets].

Use `StorageProtocol` and `StorageControlProtocol` if you want
to mock the clients in your tests.

[buckets]: https://docs.cloud.google.com/storage/docs/buckets
[objects]: https://docs.cloud.google.com/storage/docs/objects

## Quickstart

The following example demonstrates using `StorageClient`:

```swift
import Foundation
import GoogleCloudStorage

func sample(bucket: String, object: String) async throws {
  let client = try StorageClient()

  // Upload an object from memory
  let data = Data("Hello, World!".utf8)
  _ = try await client.writeObject(data, to: bucket, as: object)

  // Download the object
  let reader = client.readObject(from: bucket, object: object)
  for try await chunk in reader.body {
    print("Received \(chunk.count) bytes")
  }
}
```

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-cloud-storage` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-cloud-storage.git --from 0.3.0
```

Then add `GoogleCloudStorage` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudStorage <target-name> --package swift-google-cloud-storage
```

## Troubleshooting

For questions, bug reports, or feature requests, please open an issue in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift/issues) repository.

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
