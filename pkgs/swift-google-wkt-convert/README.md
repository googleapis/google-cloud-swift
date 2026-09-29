# Google Cloud Client Libraries for Swift - Well-Known Types Protobuf Conversions

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-wkt-convert%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/googleapis/swift-google-wkt-convert)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgoogleapis%2Fswift-google-wkt-convert%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/googleapis/swift-google-wkt-convert)

Conversions between `GoogleWKT` types and `SwiftProtobuf` Well-Known Types.

## Overview

`GoogleWKTConvert` provides bidirectional conversions between `GoogleWKT`
types (`WKTTimestamp`, `WKTDuration`, `WKTFieldMask`, `WKTEmpty`, and `WKTAny`)
and their corresponding `SwiftProtobuf` representations.

This package is separated from `swift-google-wkt` so that HTTP/REST client
libraries depending only on `GoogleWKT` do not pull `swift-protobuf` into their
Swift Package Manager dependency graph.

## Requirements

For the minimum supported Swift version and platform requirements, see the
[Requirements](https://github.com/googleapis/google-cloud-swift#minimum-supported-swift-version)
section in the `google-cloud-swift` repository.

## Installation

Add `swift-google-wkt-convert` as a package dependency:

```bash
swift package add-dependency https://github.com/googleapis/swift-google-wkt-convert.git --from 0.3.0
```

Then add `GoogleWKTConvert` to your target's dependencies:

```bash
swift package add-target-dependency GoogleWKTConvert <target-name> --package swift-google-wkt-convert
```

## Contributing

Contributions to this library are always welcome and highly encouraged.

All development, issues, and pull requests are managed in the
[google-cloud-swift](https://github.com/googleapis/google-cloud-swift) monorepo.
See [CONTRIBUTING.md](https://github.com/googleapis/google-cloud-swift/blob/main/CONTRIBUTING.md)
for details on getting started.

## License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
