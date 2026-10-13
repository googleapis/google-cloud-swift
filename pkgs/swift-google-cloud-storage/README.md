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

The following example demonstrates using `StorageControlClient`:

```swift
import GoogleCloudStorage

public func quickstart(
  client: StorageControlClient, projectId: String, bucketId: String
) async throws {
  let bucket =
    try await client
    .createBucket(
      request: .init().with {
        $0.parent = "projects/_"
        $0.bucketId = bucketId
        $0.bucket = .init().with { bucket in
          bucket.project = "projects/\(projectId)"
          bucket.storageClass = "STANDARD"
          bucket.location = "US"
        }
      })
  print("successfully created bucket \(bucket)")
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

Object download (`readObject`) and upload (`writeObject`) operations throw
`ReadObjectError` and `WriteObjectError` respectively, while control-plane
operations on `StorageControlClient` throw `RequestError`.

For detailed guidance on handling checksum mismatches, resuming interrupted
downloads and uploads, choosing between `SeekableWriteObjectSource` and
`WriteObjectSource`, and using preconditions for idempotent retries, see the
[Troubleshooting Guide](Sources/GoogleCloudStorage/GoogleCloudStorage.docc/Troubleshooting.md).

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
