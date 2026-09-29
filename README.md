# Google Cloud API Client Libraries for Swift

Idiomatic Swift client libraries for
[Google Cloud Platform](https://cloud.google.com/) services.

## Quickstart

The following example demonstrates creating a bucket using `StorageControlClient`
from `GoogleCloudStorage`:

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

To add `swift-google-cloud-storage` to your project using Swift Package Manager:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-cloud-storage.git --from 0.3.0
swift package add-target-dependency GoogleCloudStorage <target-name> --package swift-google-cloud-storage
```

For a step-by-step tutorial including authentication and project configuration, see
the [Getting Started Guide](https://googleapis.github.io/google-cloud-swift/UserGuide/documentation/userguide/quickstart).

## Documentation

- [User Guide & Hosted Documentation](https://googleapis.github.io/google-cloud-swift/UserGuide/documentation/userguide):
  Comprehensive guides for authentication, error handling, retries, long-running
  operations, pagination, package traits, and service-specific usage.
- [User Guide Sources (`guide/`)](guide/Sources/UserGuide/UserGuide.docc/): Local
  DocC source files in this repository.

## Requirements

<a name="minimum-supported-swift-version"></a>

### Minimum Supported Swift Version

We support and test the last 3 minor releases of Swift (currently Swift 6.2, 6.3,
and 6.4). We periodically update the minimum supported version as new Swift
versions become available.

### Supported Platforms

- **Linux**: Fully supported for server-side environments. Tested on Ubuntu 24.04 and compatible distributions without requiring platform configuration in `Package.swift`.
- **macOS**: Supported on macOS 15 or later for local development and deployment. When building on macOS, configure your `Package.swift` with `platforms: [.macOS(.v15)]`.

## Status and Stability

This project is currently in **Public Preview** (versioned at `0.x`). While the
libraries are functional and actively maintained, APIs may undergo refinements
before 1.0 General Availability (GA).

## Semantic versioning

We will make every effort to avoid breaking changes once a library reaches 1.0.

With that said, many packages in this project are automatically generated from
service specifications. From time to time these service specifications may
introduce breaking changes. We make reasonable efforts, and use tooling, to
detect such breaking changes. When we detect a breaking change we will bump the
major version (or minor version for packages still at `0.x`).

We do not consider changes to `swift-tools-version` to be breaking changes.

We do not consider changes to our dependencies, or the package traits enabled in
our dependencies, to be breaking changes. You should add any dependencies to
your application directly, and enable any non-default package traits of these
dependencies explicitly.

### Public API and Stability

This project follows Google's [OSS Library Breaking Change Policy].

Our public API consists of the library products declared in each package's
`Package.swift` and their exported `public` and `open` symbols. Symbols prefixed
with `_`, annotated with `@_spi(GoogleCloudInternal)`, or residing in
non-exported targets are internal implementation details and may change without
notice.

For full details and consumer guidelines, see the [Public API Policy].

## Contributing

Contributions to this library are always welcome and highly encouraged.

See [CONTRIBUTING] for more information on how to get started. You may also find
the [Set Up Development Environment] guide useful.

## License

Apache 2.0 - See [LICENSE] for more information.

[contributing]: CONTRIBUTING.md
[license]: LICENSE
[oss library breaking change policy]: https://opensource.google/documentation/policies/library-breaking-change
[public api policy]: doc/public-api.md
[set up development environment]: doc/contributor/howto-guide-set-up-development-environment.md
