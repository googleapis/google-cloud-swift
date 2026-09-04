# Google Cloud Client Libraries for Swift - Well-Known Types (WKT)

Idiomatic Swift implementations of Protocol Buffers Well-Known Types.

## Overview

`GoogleCloudWKT` provides Swift implementations of Well-Known Types (WKT) for
[Protocol Buffers](https://protobuf.dev/reference/protobuf/google.protobuf/)
and [Discovery](https://docs.cloud.google.com/docs/discovery/type-format)
used across Google Cloud APIs.

While standard Swift and Foundation libraries offer types like `Date` and
`Duration`, their precision, range, and JSON serialization semantics differ from
the Protocol Buffers specifications. This package bridges that gap by providing
strongly-typed, high-precision representations that strictly follow Google Cloud
API conventions and ProtoJSON mapping rules.

## Key Types

- **`Timestamp`**: UTC point in time with nanosecond resolution covering years
  0001-01-01 to 9999-12-31. Serializes to and from RFC 3339 formatted strings
  (e.g., `"2026-09-03T19:48:28.000000000Z"`). Avoids the valid range and
  precision limits of `Foundation.Date`.
- **`Duration`**: Signed, fixed-length time span with nanosecond resolution.
  Serializes to and from decimal strings with an `"s"` suffix (e.g., `"3.5s"`).
- **`FieldMask`**: Represents a set of symbolic field paths for partial update
  requests and read projections. Automatically converts to and from
  comma-separated camelCase strings in JSON (e.g.,
  `"displayName,userProfile.avatarUrl"`).
- **`Any`**: Container for arbitrary serialized messages accompanied by a
  `@type` URL identifier.
- **`Struct`, `Value`, `ListValue`, `NullValue`**: Dynamic JSON-compatible data
  structures for APIs that produce or consume unstructured payloads.
- **Wrapper Types**: Swift typealiases for nullable primitive wrappers
  (`StringValue`, `Int32Value`, `Int64Value`, `UInt32Value`, `UInt64Value`,
  `FloatValue`, `DoubleValue`, `BoolValue`, `BytesValue`).
- **`Recursive`**: Box wrapper enabling self-referential or recursively nested
  fields in API models without infinite layout size.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-wkt` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-wkt.git --from 0.1.0
```

Then add `GoogleCloudWKT` to your target's dependencies:

```bash
swift package add-target-dependency GoogleCloudWKT <target-name> --package swift-google-wkt
```

## Usage

### Timestamp

`Timestamp` represents a point in time independent of timezone or calendar:

```swift
import Foundation
import GoogleCloudWKT

// Create a Timestamp with seconds and nanoseconds
let timestamp = try Timestamp(seconds: 1_700_000_000, nanos: 500_000_000)
print("Seconds: \(timestamp.seconds), Nanos: \(timestamp.nanos)")

// Encodes to and decodes from RFC 3339 formatted JSON strings
let encoder = JSONEncoder()
let data = try encoder.encode(timestamp) // "2023-11-14T22:13:20.500000000Z"

let decoded = try JSONDecoder().decode(Timestamp.self, from: data)
```

### Duration

`Duration` represents a fixed-length span of time:

```swift
import Foundation
import GoogleCloudWKT

// Create a Duration of 45.25 seconds
let duration = try Duration(seconds: 45, nanos: 250_000_000)

// Encodes in JSON to "45.250000000s"
let data = try JSONEncoder().encode(duration)
let decoded = try JSONDecoder().decode(Duration.self, from: data)
```

### FieldMask

`FieldMask` is used for partial update operations and projection filters:

```swift
import Foundation
import GoogleCloudWKT

// Specify the paths to update
let mask = FieldMask(paths: ["display_name", "billing_account.id"])

// Encodes in ProtoJSON as comma-separated camelCase: "displayName,billingAccountId"
let data = try JSONEncoder().encode(mask)
let decoded = try JSONDecoder().decode(FieldMask.self, from: data)
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
