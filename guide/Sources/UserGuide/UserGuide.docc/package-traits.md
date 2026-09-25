# Package traits

Swift Package Manager supports package traits (SE-0450) starting in Swift 6.2.
Package traits allow packages to conditionally compile parts of a library,
enabling only the features and dependencies needed by the application.

## Why client libraries use traits

Several Google Cloud APIs define large numbers of independent services. For
example, Google Compute Engine v1 defines over 120 services, and Vertex AI
defines over 30 services. Generating and compiling every client and its
associated request, response, and model types would result in long compile times
and larger binary sizes, even when an application only interacts with one or two
services.

To optimize build performance, Google Cloud client libraries for Swift use
package traits to partition large libraries. Enabling a trait conditionally
compiles the specific service client and all the types required to use that
client.

## Default traits

Packages that use traits define a sensible set of default traits for commonly
used services. For example, Compute Engine enables only `Instances` (and
transitively `ZoneOperations`) by default.

When you add a dependency without specifying any traits, Swift Package Manager
enables the default traits automatically:

```swift
.package(url: "https://github.com/googleapis/swift-google-cloud-compute-v1.git", from: "0.2.0")
```

If the default traits provide all the services your application needs, no further
configuration is required.

## Enabling additional traits

To enable services beyond the defaults, specify the desired traits in your
`Package.swift` file.

### Combining default traits with additional traits

To keep the default services and enable additional services, include the
special `".defaults"` trait alongside your desired traits:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApplication",
    dependencies: [
        .package(
            url: "https://github.com/googleapis/swift-google-cloud-compute-v1.git",
            from: "0.2.0",
            traits: [".defaults", "Disks"]
        ),
    ],
    targets: [
        .target(
            name: "MyApplication",
            dependencies: [
                .product(name: "GoogleCloudComputeV1", package: "swift-google-cloud-compute-v1"),
            ]
        ),
    ]
)
```

### Disabling defaults and selecting specific traits

To disable the default traits and only compile specific services, list the
desired traits without `".defaults"`:

```swift
.package(
    url: "https://github.com/googleapis/swift-google-cloud-compute-v1.git",
    from: "0.2.0",
    traits: ["Disks"]
)
```

## Compiler diagnostics for unenabled traits

If your code attempts to use a client whose trait has not been enabled in
`Package.swift`, the Swift compiler produces an actionable diagnostic:

```
error: 'DisksClient' is unavailable: Enable the 'Disks' trait in Package.swift to use this client.
```

This diagnostic indicates precisely which trait needs to be added to your
`Package.swift` dependencies.

## Command-line workflows

When developing, testing, or building from the command line, you can enable
traits using the `--traits` option with `swift build` or `swift test`:

```bash
swift build --traits defaults,Disks
```

To build with only specific traits and bypass the defaults, omit `defaults`:

```bash
swift build --traits Disks
```

## Discovering available traits

Each generated client library documents its available traits, default traits, and
the corresponding client classes in two places:

- The `README.md` file in each package under the **Package Traits** section.
- The DocC documentation for each package in the **Package Traits** article.

## Next steps

* <doc:quickstart> describes how to set up and run your first Swift application
  with Google Cloud client libraries.
* <doc:override-endpoint> describes how to change the service endpoint.
* <doc:override-retry-policy> describes how to configure retry policies.
