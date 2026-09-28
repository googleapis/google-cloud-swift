# ``GoogleGaxGRPC``

gRPC transport support for Google Cloud Client Libraries for Swift.

## Overview

This library is only used as an implementation detail for other `swift-google-*`
packages. It contains no public APIs intended for general use.

`GoogleGaxGRPC` provides the gRPC transport implementation and error-mapping
utilities used by Google Cloud client libraries that communicate over gRPC.
Configuration of endpoints, credentials, retry policies, and request options
is shared with `GoogleGax`.
