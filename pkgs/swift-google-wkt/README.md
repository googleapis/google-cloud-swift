# Google Cloud Client Libraries for Swift - Well-Known Types (WKT)

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-wkt%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-wkt)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-wkt%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-wkt)

Idiomatic Swift implementations of Protocol Buffers Well-Known Types.

## Overview

`GoogleWKT` provides Swift implementations of Well-Known Types (WKT) for
[Protocol Buffers](https://protobuf.dev/reference/protobuf/google.protobuf/)
and [Discovery](https://docs.cloud.google.com/docs/discovery/type-format)
used across Google Cloud APIs.

While standard Swift and Foundation libraries offer types like `Date` and
`Duration`, their precision, range, and JSON serialization semantics differ from
the Protocol Buffers specifications. This package bridges that gap by providing
strongly-typed, high-precision representations that strictly follow Google Cloud
API conventions and ProtoJSON mapping rules.

## Key Types

- **`WKTTimestamp`**: UTC point in time with nanosecond resolution covering years
  0001-01-01 to 9999-12-31. Serializes to and from RFC 3339 formatted strings
  (e.g., `"2026-09-03T19:48:28.000000000Z"`). Avoids the valid range and
  precision limits of `Foundation.Date`.
- **`WKTDuration`**: Signed, fixed-length time span with nanosecond resolution.
  Serializes to and from decimal strings with an `"s"` suffix (e.g., `"3.5s"`).
- **`WKTFieldMask`**: Represents a set of symbolic field paths for partial update
  requests and read projections. Automatically converts to and from
  comma-separated camelCase strings in JSON (e.g.,
  `"displayName,userProfile.avatarUrl"`).
- **`WKTAny`**: Container for arbitrary serialized messages accompanied by a
  `@type` URL identifier.
- **`WKTEmpty`**: An empty request or response message, automatically converted
  to `Void` where appropriate by client libraries.

### Embedded JSON Objects

Some APIs use dynamic JSON-compatible data structures to represent parts of their
request or response payloads:
- `WKTStruct`, `WKTValue`, `WKTListValue`, `WKTNullValue`

### Optional Primitive Values

APIs using Protocol Buffers wrapper types represent optional or nullable fields via:
- `WKTStringValue`, `WKTInt32Value`, `WKTInt64Value`, `WKTUInt32Value`, `WKTUInt64Value`
- `WKTFloatValue`, `WKTDoubleValue`, `WKTBoolValue`, `WKTBytesValue`

### Recursive Field Wrapper

- **`WKTRecursive`**: Box wrapper enabling self-referential or recursively nested
  fields in API models without infinite value type layout size.

### API Introspection

- **`WKTApi`**: Introspection types for services that consume or expose API definitions
  as part of their operations.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-wkt` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-wkt.git --from 0.1.0
```

Then add `GoogleWKT` to your target's dependencies:

```bash
swift package add-target-dependency GoogleWKT <target-name> --package swift-google-wkt
```

## Usage

### Timestamp (WKTTimestamp)

`WKTTimestamp` represents a point in time independent of timezone or calendar:

```swift
import Foundation
import GoogleWKT

// Create a WKTTimestamp with seconds and nanoseconds
let timestamp = try WKTTimestamp(seconds: 1_700_000_000, nanos: 500_000_000)
print("Seconds: \(timestamp.seconds), Nanos: \(timestamp.nanos)")

// Encodes to and decodes from RFC 3339 formatted JSON strings
let encoder = JSONEncoder()
let data = try encoder.encode(timestamp) // "2023-11-14T22:13:20.500000000Z"

let decoded = try JSONDecoder().decode(WKTTimestamp.self, from: data)
```

### Duration (WKTDuration)

`WKTDuration` represents a fixed-length span of time:

```swift
import Foundation
import GoogleWKT

// Create a WKTDuration of 45.25 seconds
let duration = try WKTDuration(seconds: 45, nanos: 250_000_000)

// Encodes in JSON to "45.250000000s"
let data = try JSONEncoder().encode(duration)
let decoded = try JSONDecoder().decode(WKTDuration.self, from: data)
```

### FieldMask (WKTFieldMask)

`WKTFieldMask` is used for partial update operations and projection filters:

```swift
import Foundation
import GoogleWKT

// Specify the paths to update
let mask: WKTFieldMask = ["display_name", "billing_account.id"]

// Formatted as comma-separated camelCase: "displayName,billingAccountId"
print(mask)

// Encodes in ProtoJSON as comma-separated camelCase: "displayName,billingAccountId"
let data = try JSONEncoder().encode(mask)
let decoded = try JSONDecoder().decode(WKTFieldMask.self, from: data)
```

## See Also

- [Protocol Buffers Well-Known Types Reference](https://protobuf.dev/reference/protobuf/google.protobuf/)
- [Proto3 JSON Mapping Specification](https://protobuf.dev/programming-guides/proto3/#json)

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
