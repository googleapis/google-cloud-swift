# The `google-cloud-swift` Public API

This document describes what constitutes the public API for libraries in the `google-cloud-swift` project and outlines our API stability guarantees.

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) and Google's [OSS Library Breaking Change Policy](https://opensource.google/documentation/policies/library-breaking-change). Breaking changes to the public API require increasing the major version number (or minor version number for packages at `0.x`).

---

## What is Included in the Public API

The public API includes:

- **Package Products**: Swift Package Manager library products explicitly declared under `products:` in each `Package.swift` (e.g., `GoogleCloudStorage`, `GoogleCloudAuth`, `GoogleCloudGax`, `GoogleCloudWKT`).
- **Exported Public and Open Symbols**: Any `public` or `open` type (`struct`, `class`, `enum`, `actor`, `protocol`, `typealias`), function, initializer, property, subscript, or enum case exported by a product module, unless explicitly excluded below.
- **Documented Environment Variables**: Environment variables documented as configuration points (e.g., `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`).

---

## What is Excluded from the Public API

The following are implementation details and are **not** part of the public API. They may change or be removed at any time without a major version bump:

- **System Programming Interfaces (`@_spi`)**: Any declaration marked with `@_spi(GoogleCloudInternal)` (or any other SPI identifier). These symbols exist solely for coordination between packages in this repository. Downstream applications must **never** use `@_spi import`.
- **Underscored Symbols**: Any symbol beginning with an underscore (`_`), or any initializer whose first parameter label begins with an underscore (e.g., `_gapicApiClientHeader`, `_CRC32C`).
- **Internal Targets**: Targets in `Package.swift` that are not exported in `products:` (for example, internal protobuf targets).
- **Non-Public Access Levels**: Declarations marked `package`, `internal`, `fileprivate`, or `private`. In particular, the Swift 6 `package` access level is scoped to the package boundary and is not public to external consumers.
- **Diagnostic and Telemetry Output**: The exact formatting, structure, and text of log messages, trace span names, error descriptions, and debug strings.
- **Experimental Features**: Any package, module, type, or function explicitly documented or tagged as experimental or preview.

---

## Consumer Guidelines

To prevent future SDK updates from breaking your application, please observe the following conventions:

### Protocol Conformances

- **Do not conform SDK types to external protocols**: You may conform SDK types to protocols defined within your own module. Do **not** conform SDK types to protocols from the Swift standard library, Foundation, or third-party packages (such as `Identifiable`, `Codable`, or `Hashable`). A future SDK release may add that conformance, leading to duplicate conformance compilation errors in your project.
- **Do not conform external types to SDK protocols**: Only conform your own types to SDK protocols. Do not declare conformances between third-party or standard library types and SDK protocols.

### Extensions on SDK Types

- Keep extensions on SDK types `internal` or `private` within your module.
- Avoid adding `public` extensions to SDK types unless the member signature includes custom types from your own module or is uniquely prefixed, to avoid collisions if the SDK introduces a method or property with the same name.

### Dependencies and Toolchain

- **Swift Tools Version**: We do not consider changes to `swift-tools-version` to be breaking changes.
- **Dependencies and Traits**: We do not consider updates to dependencies, or the traits enabled in dependencies, to be breaking changes. If your application depends on specific versions or traits of these dependencies, declare direct dependencies in your own `Package.swift` and enable any non-default traits explicitly.
