# Google Cloud Client Libraries for Swift - Well-Known Types (WKT)

Idiomatic Swift implementations of Protocol Buffers Well-Known Types and
ProtoJSON decoding.

## Overview

`GoogleCloudWKT` provides Swift implementations of Protocol Buffers
Well-Known Types ([WKT](https://protobuf.dev/reference/protobuf/google.protobuf/))
used across Google Cloud APIs.

While standard Swift and Foundation libraries offer types like `Date` and
`Duration`, their precision, range, and JSON serialization semantics differ from
the Protocol Buffers specifications. This package bridges that gap by providing
strongly-typed, high-precision representations that strictly follow Google Cloud
API conventions and ProtoJSON mapping rules.

In addition, this package provides `ProtoJSONDecoder` (available as
`_ProtoJSONDecoder`), a specialized JSON decoder tailored to the ProtoJSON
specification required by Google Cloud REST APIs.

## Libraries & Products

This package provides two products:

- **`GoogleCloudWKT`**: Foundational types (`Timestamp`, `Duration`, `FieldMask`,
  `Any`, dynamic JSON values, primitive wrappers) and the `_ProtoJSONDecoder`
  engine with ProtoJSON Codable support.
- **`GoogleCloudWKTConvert`**: Interoperability extensions for converting between
  `GoogleCloudWKT` types and Apple's `SwiftProtobuf` types.

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

## ProtoJSON and ProtoJSONDecoder

Google Cloud APIs use HTTP+JSON (ProtoJSON) as their primary REST transport.
ProtoJSON follows the [canonical Proto3 JSON Mapping specification](https://protobuf.dev/programming-guides/proto3/#json),
which differs significantly from standard JSON decoding behavior.

### Why Standard `JSONDecoder` Is Insufficient

Attempting to decode Google Cloud API responses using standard
`Foundation.JSONDecoder` frequently causes unexpected decoding failures:

1. **Omitted Default Values**: In ProtoJSON, fields containing default values
   (empty strings `""`, numeric zeros `0` or `0.0`, booleans set to `false`,
   empty lists `[]`, and empty dictionaries `{}`) are omitted from the wire
   payload by the server to conserve bandwidth. Standard `JSONDecoder` expects
   keys to exist for non-optional properties and throws
   `DecodingError.keyNotFound`.
2. **Numbers Represented as Strings**: To prevent 64-bit integer precision loss
   in environments that use IEEE 754 floating-point numbers (such as JavaScript),
   ProtoJSON serializes 64-bit integers (`int64`, `uint64`) as quoted strings
   (e.g., `"1234567890"`). Standard `JSONDecoder` throws type mismatch errors
   when encountering strings where integer types are expected.
3. **Special Floating-Point Values**: Non-numeric floating-point values
   (`NaN`, `Infinity`, and `-Infinity`) are represented in ProtoJSON as strings
   (`"NaN"`, `"Infinity"`, `"-Infinity"`), which standard parsers reject for
   numeric types.
4. **Base64 Encoded Binary Data**: Byte fields (`Data` / `BytesValue`) in
   ProtoJSON are encoded as standard base64 strings.
5. **Stringified Map Keys**: In ProtoJSON, map keys are serialized as JSON
   object keys (which must always be strings). When the map key is an integer or
   boolean, standard `JSONDecoder` cannot map string keys into numeric or
   boolean dictionary keys.

### Why `ProtoJSONDecoder` Should Be Used

`_ProtoJSONDecoder` is designed specifically to solve these differences while
building on top of Swift's native JSON decoding infrastructure:

- **Automatic Default Value Synthesis**: When a key is missing from the payload,
  `_ProtoJSONDecoder` intercepts the missing key and synthesizes its default
  value (`""`, `0`, `false`, `[]`, `[:]`, or empty `Data`) via `DecodeToDefault`,
  matching Protocol Buffers semantics without requiring every property in generated
  models to be declared as an optional (`?`).
- **Flexible Numeric and String Parsing**: Seamlessly decodes numeric types from
  either numeric literals or string-encoded numbers.
- **Transparent Base64 Byte Decoding**: Automatically decodes base64-encoded
  strings into `Foundation.Data`.
- **Stringified Boolean Handling**: Parses `"true"` and `"false"` strings
  directly into `Bool`.

Inside the Google Cloud Swift SDK, GAX (`HTTPClientResponse`) uses
`_ProtoJSONDecoder` internally to deserialize all HTTP responses. When writing
custom decoding logic or parsing Google Cloud REST responses directly, always use
`_ProtoJSONDecoder`.

## Requirements

- Swift 6.2 or later
- macOS 15.0+ or Linux

## Installation

Add `swift-google-wkt` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/googleapis/swift-google-wkt.git", from: "0.1.0"),
]
```

Then add `GoogleCloudWKT` (and optionally `GoogleCloudWKTConvert`) to your target
dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "GoogleCloudWKT", package: "swift-google-wkt"),
        // If converting to/from SwiftProtobuf:
        // .product(name: "GoogleCloudWKTConvert", package: "swift-google-wkt"),
    ]
)
```

## Usage

### Decoding with `_ProtoJSONDecoder`

`_ProtoJSONDecoder` is exported under `@_spi(GoogleCloudInternal)`. It handles
omitted default fields, base64 data, and string-encoded numbers automatically:

```swift
import Foundation
@_spi(GoogleCloudInternal) import GoogleCloudWKT

// Example message model with non-optional properties
struct SecretPayload: Decodable, Equatable {
    var data: Data = Data()
    var dataCrc32c: Int64 = 0
}

// Server response where `dataCrc32c` was omitted because its value is 0 (default)
let json = """
{
    "data": "SGVsbG8gV29ybGQh"
}
""".data(using: .utf8)!

// Standard JSONDecoder would throw DecodingError.keyNotFound.
// _ProtoJSONDecoder correctly decodes and populates defaults:
let decoder = _ProtoJSONDecoder()
let payload = try decoder.decode(SecretPayload.self, from: json)

print(String(data: payload.data, encoding: .utf8) ?? "") // "Hello World!"
print(payload.dataCrc32c) // 0
```

### Timestamp

`Timestamp` represents a point in time independent of timezone or calendar:

```swift
import Foundation
@_spi(GoogleCloudInternal) import GoogleCloudWKT

// Create a Timestamp with seconds and nanoseconds
let timestamp = try Timestamp(seconds: 1_700_000_000, nanos: 500_000_000)
print("Seconds: \(timestamp.seconds), Nanos: \(timestamp.nanos)")

// Encodes to and decodes from RFC 3339 formatted JSON strings
let encoder = JSONEncoder()
let data = try encoder.encode(timestamp) // "2023-11-14T22:13:20.500000000Z"

let decoder = _ProtoJSONDecoder()
let decoded = try decoder.decode(Timestamp.self, from: data)
```

### Duration

`Duration` represents a fixed-length span of time:

```swift
import Foundation
@_spi(GoogleCloudInternal) import GoogleCloudWKT

// Create a Duration of 45.25 seconds
let duration = try Duration(seconds: 45, nanos: 250_000_000)

// Encodes in JSON to "45.250000000s"
let data = try JSONEncoder().encode(duration)

let decoder = _ProtoJSONDecoder()
let decoded = try decoder.decode(Duration.self, from: data)
```

### FieldMask

`FieldMask` is used for partial update operations and projection filters:

```swift
import Foundation
@_spi(GoogleCloudInternal) import GoogleCloudWKT

// Specify the paths to update
let mask = FieldMask(paths: ["display_name", "billing_account.id"])

// Encodes in ProtoJSON as comma-separated camelCase: "displayName,billingAccountId"
let data = try JSONEncoder().encode(mask)

let decoder = _ProtoJSONDecoder()
let decoded = try decoder.decode(FieldMask.self, from: data)
```

### Converting to/from SwiftProtobuf

When interoperating between `GoogleCloudWKT` and `SwiftProtobuf`, import
`GoogleCloudWKTConvert`:

```swift
import GoogleCloudWKT
import GoogleCloudWKTConvert
import SwiftProtobuf

// Convert SwiftProtobuf to GoogleCloudWKT
var proto = Google_Protobuf_Timestamp()
proto.seconds = 1_700_000_000
proto.nanos = 0

let wktTimestamp = try Timestamp(proto: proto)

// Convert back to SwiftProtobuf
let backToProto: Google_Protobuf_Timestamp = try wktTimestamp.toProto()
```

## See Also

- [Protocol Buffers Well-Known Types Reference](https://protobuf.dev/reference/protobuf/google.protobuf/)
- [Proto3 JSON Mapping Specification](https://protobuf.dev/programming-guides/proto3/#json)

## Contributing

Contributions to this library are always welcome and highly encouraged.
See [CONTRIBUTING.md](CONTRIBUTING.md) for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
