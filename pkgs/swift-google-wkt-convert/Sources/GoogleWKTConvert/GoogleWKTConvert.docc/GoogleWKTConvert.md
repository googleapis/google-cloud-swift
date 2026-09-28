# ``GoogleWKTConvert``

Conversions between `GoogleWKT` types and `SwiftProtobuf` Well-Known Types.

## Overview

This library is only used as an implementation detail for other `swift-google-*`
packages. It contains no public APIs intended for general use.

`GoogleWKTConvert` extends the core Well-Known Types in `GoogleWKT`
(`WKTTimestamp`, `WKTDuration`, `WKTFieldMask`, `WKTEmpty`, and `WKTAny`) with
initializers and methods to convert to and from their `SwiftProtobuf`
counterparts.
